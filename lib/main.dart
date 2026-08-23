import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:exif/exif.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:collection';

import 'l10n/app_localizations.dart';
import 'image_store.dart';
import 'justified_grid_layout.dart';
import 'media_filter.dart';
import 'native_lib.dart';
import 'settings_page.dart';
import 'lru_cache.dart';
import 'ui/app_theme.dart';
import 'ui/desktop_controls.dart';
import 'viewer_image.dart';
import 'worker_service.dart';

const List<String> _rawExtensions = [
  '.arw',
  '.cr2',
  '.cr3',
  '.dng',
  '.nef',
  '.orf',
  '.raf',
  '.rw2',
  '.srw',
];

const List<String> _bitmapExtensions = [
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
];

const List<String> _supportedExtensions = [
  ..._rawExtensions,
  ..._bitmapExtensions,
];

// File classification only.
//
// The displayed image source has one more layer of meaning:
// - bitmap files display the file itself
// - RAW files first display a fast preview layer
// - RAW files may then display a decoded RAW layer
enum _MediaKind { raw, bitmap }

class _MediaFile {
  final String path;
  final _MediaKind kind;

  const _MediaFile({required this.path, required this.kind});

  bool get isRaw => kind == _MediaKind.raw;
}

final DateFormat _timestampFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

class _MediaTimestampInfo {
  final DateTime? capturedAt;
  final DateTime modifiedAt;

  const _MediaTimestampInfo({
    required this.capturedAt,
    required this.modifiedAt,
  });

  DateTime getDisplayTime(TimeDisplaySource source) {
    switch (source) {
      case TimeDisplaySource.capturedAt:
        return capturedAt ?? modifiedAt;
      case TimeDisplaySource.modifiedAt:
        return modifiedAt;
    }
  }

  String format(TimeDisplaySource source) {
    return _timestampFormatter.format(getDisplayTime(source));
  }
}

class _TimestampRepository {
  // Bounded so browsing a very large directory cannot grow this without limit.
  static const int _maxEntries = 2048;
  final LinkedHashMap<String, Future<_MediaTimestampInfo>> _futureCache =
      LinkedHashMap<String, Future<_MediaTimestampInfo>>();

  Future<_MediaTimestampInfo> load(String filePath) {
    final existing = _futureCache.remove(filePath);
    if (existing != null) {
      _futureCache[filePath] = existing; // Refresh recency.
      return existing;
    }

    final future = _readTimestampInfo(filePath);
    _futureCache[filePath] = future;
    while (_futureCache.length > _maxEntries) {
      _futureCache.remove(_futureCache.keys.first);
    }
    return future;
  }

  void clear() {
    _futureCache.clear();
  }

  // Read only the first portion of the file for EXIF parsing to avoid
  // loading entire multi-MB RAW files into memory (which causes OOM crashes
  // when many files are opened concurrently).
  static const int _exifReadSize = 128 * 1024; // 128 KB

  Future<_MediaTimestampInfo> _readTimestampInfo(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    final modifiedAt = stat.modified;
    DateTime? capturedAt;

    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final length = await raf.length();
        final readLength = length < _exifReadSize ? length : _exifReadSize;
        final bytes = await raf.read(readLength);
        capturedAt = await _parseCapturedAtFromBytes(bytes);
      } finally {
        await raf.close();
      }
    } catch (_) {
      capturedAt = null;
    }

    return _MediaTimestampInfo(capturedAt: capturedAt, modifiedAt: modifiedAt);
  }
}

// Runs on a helper isolate: EXIF parsing is pure CPU work and parsing it inline
// stutters the grid when many tiles resolve their timestamps at once.
Future<DateTime?> _parseCapturedAtFromBytes(Uint8List bytes) {
  return Isolate.run(() => _parseCapturedAtFromBytesSync(bytes));
}

Future<DateTime?> _parseCapturedAtFromBytesSync(Uint8List bytes) async {
  try {
    final data = await readExifFromBytes(bytes);
    final rawValue = data['Image DateTime']?.printable ??
        data['EXIF DateTimeOriginal']?.printable ??
        data['EXIF DateTimeDigitized']?.printable;
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return _parseExifDateTime(rawValue);
  } catch (_) {
    return null;
  }
}

DateTime? _parseExifDateTime(String value) {
  final normalized = value.trim();
  final exifMatch = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(normalized);
  if (exifMatch != null) {
    return DateTime(
      int.parse(exifMatch.group(1)!),
      int.parse(exifMatch.group(2)!),
      int.parse(exifMatch.group(3)!),
      int.parse(exifMatch.group(4)!),
      int.parse(exifMatch.group(5)!),
      int.parse(exifMatch.group(6)!),
    );
  }
  return DateTime.tryParse(normalized);
}

/// Granularity of decode-target widths, in physical pixels.
const int kDecodeWidthBucket = 128;

/// Rounds a desired decode width up to the next [kDecodeWidthBucket] step.
///
/// Decode targets double as cache keys, so a continuously-varying width (window
/// resize, DPR changes) would otherwise invalidate every cached image.
int bucketDecodeWidth(double width) {
  if (width <= kDecodeWidthBucket) return kDecodeWidthBucket;
  return (width / kDecodeWidthBucket).ceil() * kDecodeWidthBucket;
}

const MethodChannel _desktopOpenChannel = MethodChannel('rawviewer/open_paths');
const MethodChannel _windowsShellChannel =
    MethodChannel('rawviewer/windows_shell');

enum _OpenedSourceKind { none, folder, files }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('window_width') ?? 1024.0;
    final height = prefs.getDouble('window_height') ?? 768.0;
    final x = prefs.getDouble('window_x');
    final y = prefs.getDouble('window_y');
    final isMaximized = prefs.getBool('window_maximized') ?? false;

    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      center: (x == null || y == null),
      title: 'Raw Viewer',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      if (isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  Locale? _locale;

  // Resize/move fire continuously while dragging; persist only once the user
  // settles instead of hitting the disk on every event.
  static const Duration _windowPersistDelay = Duration(milliseconds: 300);
  Timer? _windowGeometryTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    _windowGeometryTimer?.cancel();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _scheduleWindowGeometrySave() {
    _windowGeometryTimer?.cancel();
    _windowGeometryTimer = Timer(_windowPersistDelay, _persistWindowGeometry);
  }

  Future<void> _persistWindowGeometry() async {
    try {
      if (await windowManager.isMaximized()) return;

      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width', size.width);
      await prefs.setDouble('window_height', size.height);
      await prefs.setDouble('window_x', position.dx);
      await prefs.setDouble('window_y', position.dy);
    } catch (_) {
      // Window may already be gone; losing geometry is not worth surfacing.
    }
  }

  @override
  void onWindowResized() {
    _scheduleWindowGeometrySave();
  }

  @override
  void onWindowMoved() {
    _scheduleWindowGeometrySave();
  }

  @override
  void onWindowMaximize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('window_maximized', true);
  }

  @override
  void onWindowUnmaximize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('window_maximized', false);
  }

  void _handleAppLanguageChanged(AppLanguage language) {
    setState(() {
      _locale = language.locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        locale: _locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh'),
        ],
        theme: rawViewerTheme,
        home: HomePage(onAppLanguageChanged: _handleAppLanguageChanged),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  final ValueChanged<AppLanguage> onAppLanguageChanged;

  const HomePage({
    super.key,
    required this.onAppLanguageChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _currentDirectoryPath;
  int? _openedDirectoryCount;
  String? _lastSyncedWindowsContextMenuText;
  List<_MediaFile> _files = [];
  _OpenedSourceKind _openedSourceKind = _OpenedSourceKind.none;
  // Use LRU Cache to limit memory usage.
  late LruCache<String, ViewerImage> _imageCache;
  late ImageStore _imageStore;
  final _TimestampRepository _timestampRepository = _TimestampRepository();
  ViewerSettings _settings = const ViewerSettings();
  MediaFilter _mediaFilter = MediaFilter.all;
  int _crossAxisCount = 4;
  bool _hasUserConfiguredGridAspectRatio = false;
  final Map<String, double> _mediaAspectRatios = <String, double>{};
  final Map<String, double> _pendingMediaAspectRatios = <String, double>{};
  bool _mediaAspectRatioUpdateScheduled = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initCache();
    unawaited(_listenForDesktopOpenRequests());
    unawaited(_refreshWindowsContextMenuState());
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGridAspectRatio = GridAspectRatio.values
        .asNameMap()[prefs.getString('grid_aspect_ratio')];
    if (!mounted) {
      return;
    }
    setState(() {
      _crossAxisCount = prefs.getInt('grid_cross_axis_count') ?? 4;
      if (!_hasUserConfiguredGridAspectRatio) {
        _settings = _settings.copyWith(
          gridAspectRatio: savedGridAspectRatio ?? GridAspectRatio.ratio3x2,
        );
      }
    });
  }

  Future<void> _updateCrossAxisCount(int delta) async {
    final newCount = (_crossAxisCount + delta).clamp(1, 10);
    if (newCount == _crossAxisCount) return;

    setState(() {
      _crossAxisCount = newCount;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('grid_cross_axis_count', newCount);
  }

  Future<void> _persistGridAspectRatio(GridAspectRatio ratio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('grid_aspect_ratio', ratio.name);
  }

  void _updateSettings(ViewerSettings settings) {
    final cacheSizeChanged = _settings.maxCacheSize != settings.maxCacheSize;
    final appLanguageChanged = _settings.appLanguage != settings.appLanguage;
    final gridAspectRatioChanged =
        _settings.gridAspectRatio != settings.gridAspectRatio;

    setState(() {
      _settings = settings;
    });

    if (cacheSizeChanged) {
      _replaceCache();
    }
    if (appLanguageChanged) {
      widget.onAppLanguageChanged(settings.appLanguage);
    }
    if (gridAspectRatioChanged) {
      _hasUserConfiguredGridAspectRatio = true;
      unawaited(_persistGridAspectRatio(settings.gridAspectRatio));
    }
  }

  void _initCache() {
    // maxCacheSize is in MB, convert to bytes
    final int maxBytes = _settings.maxCacheSize * 1024 * 1024;
    _imageCache = LruCache(
      maxBytes,
      sizeOf: (image) => image.sizeInBytes,
      // Evicted entries own a live ui.Image handle; dropping the reference is
      // not enough to release the texture.
      onEvict: (_, image) => image.dispose(),
    );
    _imageStore = ImageStore(_imageCache);
  }

  void _replaceCache() {
    final oldCache = _imageCache;
    _initCache();
    oldCache.clear();
  }

  Future<void> _refreshWindowsContextMenuState() async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      final contextMenuSettings = await _getWindowsContextMenuSettings();
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = _settings.copyWith(
          windowsContextMenu: contextMenuSettings,
        );
      });
    } on MissingPluginException {
      // Ignore when shell integration is not implemented on this platform.
    } on PlatformException {
      // Ignore transient Windows shell integration failures at startup.
    }
  }

  Future<WindowsContextMenuSettings> _getWindowsContextMenuSettings() async {
    final values = await _windowsShellChannel.invokeMapMethod<String, dynamic>(
      'getContextMenuState',
    );
    return WindowsContextMenuSettings.fromPlatformMap(values);
  }

  Future<WindowsContextMenuSettings> _setWindowsContextMenuEnabled(
    bool enabled,
  ) async {
    try {
      final menuText =
          AppLocalizations.of(context)?.windowsContextMenuMenuText ??
              'Open in RawView';
      final values =
          await _windowsShellChannel.invokeMapMethod<String, dynamic>(
        'setContextMenuEnabled',
        {
          'enabled': enabled,
          'menuText': menuText,
        },
      );
      final nextState = WindowsContextMenuSettings.fromPlatformMap(values);

      if (mounted) {
        setState(() {
          _settings = _settings.copyWith(windowsContextMenu: nextState);
        });
      }

      return nextState;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Unknown platform error');
    } on MissingPluginException {
      throw Exception(
          'Windows shell integration is not supported in this build');
    }
  }

  Future<void> _syncWindowsContextMenuLanguage(String menuText) async {
    if (!Platform.isWindows || !_settings.windowsContextMenu.enabled) {
      _lastSyncedWindowsContextMenuText = null;
      return;
    }

    if (_lastSyncedWindowsContextMenuText == menuText) {
      return;
    }

    _lastSyncedWindowsContextMenuText = menuText;

    try {
      final nextState = await _setWindowsContextMenuEnabled(true);
      if (!mounted) {
        return;
      }

      setState(() {
        _settings = _settings.copyWith(windowsContextMenu: nextState);
      });
    } catch (_) {
      _lastSyncedWindowsContextMenuText = null;
      // Ignore language sync failures and keep current integration state.
    }
  }

  Future<void> _openFolder() async {
    if (Platform.isAndroid) {
      // Request permissions for file access
      // For Android 11+ (API 30+)
      if (await Permission.manageExternalStorage.status.isDenied) {
        await Permission.manageExternalStorage.request();
      }
      // For older Android or if generic storage permission is needed
      if (await Permission.storage.status.isDenied) {
        await Permission.storage.request();
      }
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();

    if (selectedDirectory != null) {
      await _handleIncomingPaths([selectedDirectory]);
    }
  }

  Future<void> _openFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: _supportedExtensions
          .map((extension) => extension.replaceFirst('.', ''))
          .toList(),
    );

    final selectedFiles = result?.paths.whereType<String>().toList();
    if (selectedFiles == null || selectedFiles.isEmpty) {
      return;
    }

    await _handleIncomingPaths(selectedFiles);
  }

  Future<void> _listenForDesktopOpenRequests() async {
    if (!Platform.isMacOS && !Platform.isWindows) {
      return;
    }

    _desktopOpenChannel.setMethodCallHandler((call) async {
      if (call.method != 'openPaths') {
        throw MissingPluginException('Unsupported method: ${call.method}');
      }

      final arguments = call.arguments;
      if (arguments is! List) {
        return;
      }

      await _handleIncomingPaths(arguments.whereType<String>().toList());
    });

    try {
      final initialPaths =
          await _desktopOpenChannel.invokeListMethod<String>('getInitialPaths');
      if (initialPaths != null && initialPaths.isNotEmpty) {
        await _handleIncomingPaths(initialPaths);
      }
    } on MissingPluginException {
      // Ignore when the current platform does not expose desktop open events.
    } on PlatformException {
      // Ignore malformed payloads from the host platform.
    }
  }

  Future<void> _handleIncomingPaths(List<String> incomingPaths) async {
    final normalizedPaths = incomingPaths
        .where((filePath) => filePath.trim().isNotEmpty)
        .map((filePath) => path.normalize(path.absolute(filePath)))
        .toList();
    if (normalizedPaths.isEmpty) {
      return;
    }

    final directories = <String>[];
    final files = <_MediaFile>[];

    for (final openPath in normalizedPaths) {
      final entityType = FileSystemEntity.typeSync(openPath);
      if (entityType == FileSystemEntityType.directory) {
        directories.add(openPath);
        continue;
      }
      if (entityType == FileSystemEntityType.file) {
        final mediaFile = _mediaFileFromPath(openPath);
        if (mediaFile != null) {
          files.add(mediaFile);
        }
      }
    }

    if (directories.isNotEmpty) {
      final directoryFiles = directories.expand(_listRawFilesInDirectory);
      final nextFiles = _deduplicateMediaFiles([...directoryFiles, ...files]);
      _applyOpenedFiles(
        files: nextFiles,
        sourceKind: _OpenedSourceKind.folder,
        clearCache: true,
        openedDirectoryPath: directories.length == 1 ? directories.first : null,
        openedDirectoryCount: directories.length,
      );
      return;
    }

    if (files.isEmpty) {
      return;
    }

    final shouldReplaceCurrent = _openedSourceKind != _OpenedSourceKind.files;
    final nextFiles = shouldReplaceCurrent
        ? files
        : _deduplicateMediaFiles([..._files, ...files]);

    _applyOpenedFiles(
      files: nextFiles,
      sourceKind: _OpenedSourceKind.files,
      clearCache: shouldReplaceCurrent,
    );
  }

  void _applyOpenedFiles({
    required List<_MediaFile> files,
    required _OpenedSourceKind sourceKind,
    required bool clearCache,
    String? openedDirectoryPath,
    int? openedDirectoryCount,
  }) {
    if (!mounted) {
      return;
    }

    if (clearCache) {
      _imageCache.clear();
      _timestampRepository.clear();
      _mediaAspectRatios.clear();
      _pendingMediaAspectRatios.clear();
    }

    setState(() {
      _openedSourceKind = sourceKind;
      _currentDirectoryPath = openedDirectoryPath;
      _openedDirectoryCount = openedDirectoryCount;
      _files = files;
    });
  }

  List<_MediaFile> _listRawFilesInDirectory(String directoryPath) {
    final files = Directory(directoryPath)
        .listSync()
        .whereType<File>()
        .map((file) => _mediaFileFromPath(file.path))
        .whereType<_MediaFile>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  List<_MediaFile> _deduplicateMediaFiles(Iterable<_MediaFile> files) {
    final seen = <String>{};
    final result = <_MediaFile>[];

    for (final mediaFile in files) {
      final normalizedPath = path.normalize(path.absolute(mediaFile.path));
      if (seen.add(normalizedPath)) {
        result.add(_MediaFile(path: normalizedPath, kind: mediaFile.kind));
      }
    }

    return result;
  }

  _MediaFile? _mediaFileFromPath(String filePath) {
    final normalizedPath = path.normalize(path.absolute(filePath));
    final extension = path.extension(normalizedPath).toLowerCase();
    if (_rawExtensions.contains(extension)) {
      return _MediaFile(path: normalizedPath, kind: _MediaKind.raw);
    }
    if (_bitmapExtensions.contains(extension)) {
      return _MediaFile(path: normalizedPath, kind: _MediaKind.bitmap);
    }
    return null;
  }

  String _currentTitle(AppLocalizations l10n) {
    if (_openedSourceKind == _OpenedSourceKind.folder) {
      if (_openedDirectoryCount == 1 && _currentDirectoryPath != null) {
        return _currentDirectoryPath!;
      }
      if ((_openedDirectoryCount ?? 0) > 1) {
        return l10n.folderSelectionTitle(_openedDirectoryCount!);
      }
    }

    if (_openedSourceKind == _OpenedSourceKind.files && _files.isNotEmpty) {
      return l10n.fileSelectionTitle(_files.length);
    }

    return l10n.appTitle;
  }

  void _updateMediaAspectRatio(String filePath, double aspectRatio) {
    if (!aspectRatio.isFinite || aspectRatio <= 0) {
      return;
    }

    final previous =
        _pendingMediaAspectRatios[filePath] ?? _mediaAspectRatios[filePath];
    if (previous != null && (previous - aspectRatio).abs() < 0.001) {
      return;
    }

    _pendingMediaAspectRatios[filePath] = aspectRatio;
    if (_mediaAspectRatioUpdateScheduled) {
      return;
    }

    _mediaAspectRatioUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mediaAspectRatioUpdateScheduled = false;
      if (!mounted || _pendingMediaAspectRatios.isEmpty) {
        return;
      }

      final updates = Map<String, double>.from(_pendingMediaAspectRatios);
      _pendingMediaAspectRatios.clear();
      setState(() {
        _mediaAspectRatios.addAll(updates);
      });
    });
  }

  Widget _buildThumbnailTile(
    List<_MediaFile> files,
    int index,
    int thumbnailResizeWidth,
  ) {
    final mediaFile = files[index];
    final filePath = mediaFile.path;
    return _MediaThumbnailTile(
      key: ValueKey(filePath),
      mediaFile: mediaFile,
      settings: _settings,
      timestampRepository: _timestampRepository,
      resizeWidth: thumbnailResizeWidth,
      imageStore: _imageStore,
      onAspectRatioChanged: _settings.gridAspectRatio.isAdaptive
          ? (ratio) => _updateMediaAspectRatio(filePath, ratio)
          : null,
      onTap: () {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) {
              return ExcludeSemantics(
                child: FadeTransition(
                  opacity: animation,
                  child: _ImagePreviewPage(
                    files: files,
                    initialIndex: index,
                    thumbnailResizeWidth: thumbnailResizeWidth,
                    imageStore: _imageStore,
                    timestampRepository: _timestampRepository,
                    settings: _settings,
                    onClose: () {
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAdaptiveGrid(
    List<_MediaFile> files,
    int thumbnailResizeWidth,
  ) {
    const gridPadding = EdgeInsets.all(12);
    const gridSpacing = 10.0;

    return Padding(
      padding: gridPadding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final nominalCellWidth =
              (width - gridSpacing * (_crossAxisCount - 1)) / _crossAxisCount;
          final targetRowHeight = nominalCellWidth / (3 / 2);
          final rows = buildJustifiedGridRows(
            aspectRatios: files
                .map(
                  (file) =>
                      _mediaAspectRatios[file.path] ??
                      GridAspectRatio.adaptive.aspectRatio,
                )
                .toList(growable: false),
            availableWidth: width,
            targetRowHeight: targetRowHeight,
            spacing: gridSpacing,
          );

          return CustomScrollView(
            scrollCacheExtent: const ScrollCacheExtent.pixels(200),
            slivers: [
              SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, rowIndex) {
                  final row = rows[rowIndex];
                  return SizedBox(
                    height: row.height,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List<Widget>.generate(
                        row.indices.length,
                        (itemIndex) => Padding(
                          padding: EdgeInsets.only(
                            right: itemIndex == row.indices.length - 1
                                ? 0
                                : gridSpacing,
                          ),
                          child: SizedBox(
                            width: row.widths[itemIndex],
                            child: _buildThumbnailTile(
                              files,
                              row.indices[itemIndex],
                              thumbnailResizeWidth,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rawCount = _files.where((file) => file.isRaw).length;
    final imageCount = _files.length - rawCount;
    final filteredFiles = _files
        .where((file) => _mediaFilter.includes(isRaw: file.isRaw))
        .toList(growable: false);

    // Calculate dynamic thumbnail resize width based on grid cell size, then
    // snap it to a bucket. Without bucketing, dragging the window by one pixel
    // changes the decode target and re-decodes every visible thumbnail.
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenWidth = MediaQuery.of(context).size.width;
    final totalPadding = 16.0 + (_crossAxisCount - 1) * 8.0;
    final cellWidth = (screenWidth - totalPadding) / _crossAxisCount;
    final thumbnailResizeWidth =
        bucketDecodeWidth((cellWidth * dpr).clamp(100.0, 800.0));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncWindowsContextMenuLanguage(
        l10n.windowsContextMenuMenuText,
      ));
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _DesktopCommandBar(
              title: _currentTitle(l10n),
              crossAxisCount: _crossAxisCount,
              openFolderLabel: l10n.openFolder,
              openFilesLabel: l10n.openFiles,
              settingsTooltip: l10n.settingsTooltip,
              largerThumbnailsTooltip: l10n.largerThumbnailsTooltip,
              smallerThumbnailsTooltip: l10n.smallerThumbnailsTooltip,
              gridColumnsTooltip: l10n.gridColumnsTooltip(_crossAxisCount),
              selectedMediaFilter: _mediaFilter,
              rawCount: rawCount,
              imageCount: imageCount,
              onMediaFilterSelected: (filter) {
                setState(() {
                  _mediaFilter = filter;
                });
              },
              onDecreaseThumbnailSize:
                  _crossAxisCount > 1 ? () => _updateCrossAxisCount(-1) : null,
              onIncreaseThumbnailSize:
                  _crossAxisCount < 10 ? () => _updateCrossAxisCount(1) : null,
              onOpenSettings: _showSettings,
              onOpenFiles: _openFiles,
              onOpenFolder: _openFolder,
            ),
            Expanded(
              child: ExcludeSemantics(
                child: _files.isEmpty
                    ? _EmptyGallery(
                        message: l10n.homeEmptyState,
                        openFolderLabel: l10n.openFolder,
                        openFilesLabel: l10n.openFiles,
                        onOpenFiles: _openFiles,
                        onOpenFolder: _openFolder,
                      )
                    : filteredFiles.isEmpty
                        ? Center(child: Text(l10n.mediaFilterEmptyState))
                        : _settings.gridAspectRatio.isAdaptive
                            ? _buildAdaptiveGrid(
                                filteredFiles,
                                thumbnailResizeWidth,
                              )
                            : GridView.builder(
                                addAutomaticKeepAlives: false,
                                scrollCacheExtent:
                                    const ScrollCacheExtent.pixels(200),
                                padding: const EdgeInsets.all(12),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _crossAxisCount,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  childAspectRatio:
                                      _settings.gridAspectRatio.aspectRatio,
                                ),
                                itemCount: filteredFiles.length,
                                itemBuilder: (context, index) {
                                  return _buildThumbnailTile(
                                    filteredFiles,
                                    index,
                                    thumbnailResizeWidth,
                                  );
                                },
                              ),
              ),
            ),
            _GalleryStatusBar(
              itemCountLabel: l10n.galleryItemCount(filteredFiles.length),
              gridColumnsLabel: l10n.gridColumnsTooltip(_crossAxisCount),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    await _refreshWindowsContextMenuState();
    if (!mounted || !context.mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 640,
            height: 720,
            child: SettingsPage(
              settings: _settings,
              onSettingsChanged: _updateSettings,
              onWindowsContextMenuChanged:
                  Platform.isWindows ? _setWindowsContextMenuEnabled : null,
              onClose: () {
                Navigator.pop(dialogContext);
              },
            ),
          ),
        );
      },
    );
  }
}

class _DesktopCommandBar extends StatelessWidget {
  final String title;
  final int crossAxisCount;
  final String openFolderLabel;
  final String openFilesLabel;
  final String settingsTooltip;
  final String largerThumbnailsTooltip;
  final String smallerThumbnailsTooltip;
  final String gridColumnsTooltip;
  final MediaFilter selectedMediaFilter;
  final int rawCount;
  final int imageCount;
  final ValueChanged<MediaFilter> onMediaFilterSelected;
  final VoidCallback? onDecreaseThumbnailSize;
  final VoidCallback? onIncreaseThumbnailSize;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;

  const _DesktopCommandBar({
    required this.title,
    required this.crossAxisCount,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.settingsTooltip,
    required this.largerThumbnailsTooltip,
    required this.smallerThumbnailsTooltip,
    required this.gridColumnsTooltip,
    required this.selectedMediaFilter,
    required this.rawCount,
    required this.imageCount,
    required this.onMediaFilterSelected,
    required this.onDecreaseThumbnailSize,
    required this.onIncreaseThumbnailSize,
    required this.onOpenSettings,
    required this.onOpenFiles,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: RawViewerColors.surface,
            border: Border(bottom: BorderSide(color: RawViewerColors.border)),
          ),
          child: Row(
            children: [
              const Icon(Icons.photo_library_outlined,
                  color: RawViewerColors.accent, size: 19),
              if (!compact) ...[
                const SizedBox(width: 8),
                const Text(
                  'RAW VIEWER',
                  style: TextStyle(
                    color: RawViewerColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 16),
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(color: RawViewerColors.border),
                ),
                const SizedBox(width: 12),
              ],
              if (!compact)
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RawViewerColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                const Spacer(),
              if (!compact) ...[
                Tooltip(
                  message: gridColumnsTooltip,
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(
                      Icons.grid_view_outlined,
                      color: RawViewerColors.mutedText,
                      size: 19,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              MediaFilterButton(
                selectedFilter: selectedMediaFilter,
                rawCount: rawCount,
                imageCount: imageCount,
                onSelected: onMediaFilterSelected,
              ),
              const SizedBox(width: 4),
              DesktopIconButton(
                icon: Icons.zoom_in,
                tooltip: largerThumbnailsTooltip,
                onPressed: onDecreaseThumbnailSize,
              ),
              DesktopIconButton(
                icon: Icons.zoom_out,
                tooltip: smallerThumbnailsTooltip,
                onPressed: onIncreaseThumbnailSize,
              ),
              const SizedBox(width: 8),
              if (!compact)
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(color: RawViewerColors.border),
                ),
              if (!compact) const SizedBox(width: 8),
              DesktopIconButton(
                icon: Icons.folder_open_outlined,
                tooltip: openFolderLabel,
                onPressed: onOpenFolder,
              ),
              DesktopIconButton(
                icon: Icons.file_open_outlined,
                tooltip: openFilesLabel,
                onPressed: onOpenFiles,
              ),
              const SizedBox(width: 6),
              DesktopIconButton(
                icon: Icons.tune,
                tooltip: settingsTooltip,
                onPressed: onOpenSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  final String message;
  final String openFolderLabel;
  final String openFilesLabel;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;

  const _EmptyGallery({
    required this.message,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.onOpenFiles,
    required this.onOpenFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: RawViewerColors.surface,
                border: Border.all(color: RawViewerColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: RawViewerColors.mutedText,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RawViewerColors.mutedText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                DesktopCommandButton(
                  icon: Icons.folder_open_outlined,
                  label: openFolderLabel,
                  onPressed: onOpenFolder,
                  emphasized: true,
                ),
                DesktopCommandButton(
                  icon: Icons.file_open_outlined,
                  label: openFilesLabel,
                  onPressed: onOpenFiles,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryStatusBar extends StatelessWidget {
  final String itemCountLabel;
  final String gridColumnsLabel;

  const _GalleryStatusBar({
    required this.itemCountLabel,
    required this.gridColumnsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: RawViewerColors.surface,
        border: Border(top: BorderSide(color: RawViewerColors.mutedBorder)),
      ),
      child: Row(
        children: [
          Text(
            itemCountLabel,
            style: const TextStyle(
              color: RawViewerColors.mutedText,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            gridColumnsLabel,
            style: const TextStyle(
              color: RawViewerColors.mutedText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaThumbnailTile extends StatefulWidget {
  final _MediaFile mediaFile;
  final ViewerSettings settings;
  final _TimestampRepository timestampRepository;
  final int resizeWidth;
  final ImageStore imageStore;
  final ValueChanged<double>? onAspectRatioChanged;
  final VoidCallback onTap;

  const _MediaThumbnailTile({
    super.key,
    required this.mediaFile,
    required this.settings,
    required this.timestampRepository,
    required this.resizeWidth,
    required this.imageStore,
    this.onAspectRatioChanged,
    required this.onTap,
  });

  String get filePath => mediaFile.path;

  @override
  State<_MediaThumbnailTile> createState() => _MediaThumbnailTileState();
}

class _MediaThumbnailTileState extends State<_MediaThumbnailTile> {
  ViewerImage? _fastPreview;
  bool _failed = false;
  ImageStream? _bitmapImageStream;
  ImageStreamListener? _bitmapImageListener;

  /// Incremented whenever this tile is recycled or disposed, so a load that
  /// completes afterwards can tell that its result is no longer wanted.
  int _generation = 0;
  late Future<_MediaTimestampInfo> _timestampFuture;

  @override
  void initState() {
    super.initState();
    _startLoad();
    _timestampFuture = widget.timestampRepository.load(widget.filePath);
  }

  @override
  void didUpdateWidget(_MediaThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath ||
        widget.resizeWidth != oldWidget.resizeWidth) {
      _generation++;
      _clearPreview();
      _stopBitmapAspectRatioLoad();
      _failed = false;
      _startLoad();
      if (widget.filePath != oldWidget.filePath) {
        _timestampFuture = widget.timestampRepository.load(widget.filePath);
      }
    } else if (widget.onAspectRatioChanged != null &&
        oldWidget.onAspectRatioChanged == null) {
      if (widget.mediaFile.isRaw) {
        final preview = _fastPreview;
        if (preview != null) {
          _reportAspectRatio(preview.width / preview.height);
        }
      } else {
        _startBitmapAspectRatioLoad();
      }
    } else if (widget.onAspectRatioChanged == null &&
        oldWidget.onAspectRatioChanged != null) {
      _stopBitmapAspectRatioLoad();
    } else if (widget.settings.timeDisplaySource !=
        oldWidget.settings.timeDisplaySource) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++; // Discard any in-flight result for this tile.
    _stopBitmapAspectRatioLoad();
    _clearPreview();
    super.dispose();
  }

  void _clearPreview() {
    _fastPreview?.dispose();
    _fastPreview = null;
  }

  void _startLoad() {
    // Bitmap files go through Flutter's own file/image pipeline.
    if (!widget.mediaFile.isRaw) {
      _startBitmapAspectRatioLoad();
      return;
    }

    // A cache hit resolves synchronously, so the very first frame already has
    // the image rather than flashing a placeholder.
    final cached = widget.imageStore.peek(widget.filePath, RawLayer.fastPreview,
        targetWidth: widget.resizeWidth);
    if (cached != null) {
      _fastPreview = cached;
      _reportAspectRatio(cached.width / cached.height);
      return;
    }

    unawaited(_loadRawFastPreview(_generation));
  }

  Future<void> _loadRawFastPreview(int generation) async {
    // This layer prefers embedded preview data and falls back to a fast
    // RAW-generated preview when the file has no embedded preview.
    //
    // The task is intentionally not cancelled when this tile is recycled: the
    // worker dedupes fast previews by path, so cancelling would also resolve
    // another tile's shared request to null. Scrolling past is instead handled
    // by ignoring a stale result via [generation].
    final image = await widget.imageStore.load(
      widget.filePath,
      RawLayer.fastPreview,
      targetWidth: widget.resizeWidth,
    );

    if (!mounted || generation != _generation) {
      image?.dispose();
      return;
    }

    setState(() {
      _clearPreview();
      _fastPreview = image;
      _failed = image == null;
    });
    if (image != null) {
      _reportAspectRatio(image.width / image.height);
    }
  }

  void _startBitmapAspectRatioLoad() {
    if (widget.onAspectRatioChanged == null) {
      return;
    }

    final imageProvider = ResizeImage(
      FileImage(File(widget.filePath)),
      width: widget.resizeWidth,
    );
    final imageStream = imageProvider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((imageInfo, _) {
      _reportAspectRatio(imageInfo.image.width / imageInfo.image.height);
    });
    _bitmapImageStream = imageStream;
    _bitmapImageListener = listener;
    imageStream.addListener(listener);
  }

  void _stopBitmapAspectRatioLoad() {
    final imageStream = _bitmapImageStream;
    final listener = _bitmapImageListener;
    if (imageStream != null && listener != null) {
      imageStream.removeListener(listener);
    }
    _bitmapImageStream = null;
    _bitmapImageListener = null;
  }

  void _reportAspectRatio(double aspectRatio) {
    widget.onAspectRatioChanged?.call(aspectRatio);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: path.basename(widget.filePath),
      button: true,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        path.basename(widget.filePath),
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      FutureBuilder<_MediaTimestampInfo>(
                        future: _timestampFuture,
                        builder: (context, snapshot) {
                          final text = snapshot.hasData
                              ? snapshot.data!
                                  .format(widget.settings.timeDisplaySource)
                              : '---- -- -- --:--:--';
                          return Text(
                            text,
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: Color(0xFFD2D9DD),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (widget.mediaFile.isRaw)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 30,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xE6171A1E),
                        border: Border.all(color: const Color(0xFF525A62)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.rawShortLabel,
                        style: const TextStyle(
                          color: Color(0xFFE5E9EC),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Bitmap files: use Flutter's built-in image pipeline with resize
    if (!widget.mediaFile.isRaw) {
      return _buildBitmapThumbnail();
    }

    final preview = _fastPreview;
    if (preview != null) {
      return RawImageWidget(
        image: preview,
        fit: BoxFit.cover,
        heroTag: widget.filePath,
      );
    }

    if (_failed) {
      return Container(
        color: Colors.grey[800],
        child: const Center(child: Icon(Icons.broken_image, size: 20)),
      );
    }

    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildBitmapThumbnail() {
    Widget image = Image(
      image: ResizeImage(
        FileImage(File(widget.filePath)),
        width: widget.resizeWidth,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[800],
        child: const Center(child: Icon(Icons.broken_image, size: 20)),
      ),
    );
    return Hero(tag: widget.filePath, child: image);
  }
}

class _ImagePreviewPage extends StatefulWidget {
  final List<_MediaFile> files;
  final int initialIndex;
  final int thumbnailResizeWidth;
  final ImageStore imageStore;
  final _TimestampRepository timestampRepository;
  final ViewerSettings settings;
  final VoidCallback onClose;

  const _ImagePreviewPage({
    required this.files,
    required this.initialIndex,
    required this.thumbnailResizeWidth,
    required this.imageStore,
    required this.timestampRepository,
    required this.settings,
    required this.onClose,
  });

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late PageController _pageController;
  late int _currentIndex;
  late int _targetPage;
  bool _isLocked = false;

  DateTime? _lastSwitchTime;
  Timer? _scrollStopTimer;
  // A notifier rather than setState: flipping this must not rebuild the whole
  // PageView (and every page in it) on each scroll burst.
  final ValueNotifier<bool> _isFastScrolling = ValueNotifier<bool>(false);
  late Future<_MediaTimestampInfo> _currentTimestampFuture;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentTimestampFuture =
        widget.timestampRepository.load(widget.files[_currentIndex].path);
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _isFastScrolling.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _currentTimestampFuture =
          widget.timestampRepository.load(widget.files[_currentIndex].path);
      if ((_targetPage - index).abs() <= 1) {
        _targetPage = index;
      }
    });

    // We also preload here to cover cases where user swiped manually instead of mouse wheel
    _preloadThumbnails(index);
  }

  void _preloadThumbnails(int centerIndex, {bool isFastScrolling = false}) {
    int range = isFastScrolling ? 2 : 10;
    for (int i = 1; i <= range; i++) {
      _preloadIndex(centerIndex + i);
      _preloadIndex(centerIndex - i);
    }
  }

  void _preloadIndex(int index) {
    if (index < 0 || index >= widget.files.length) return;

    final mediaFile = widget.files[index];
    final String filePath = mediaFile.path;

    if (mediaFile.isRaw) {
      // Warms the same full-resolution entry the preview reads, so a switch onto
      // this page can paint on its first frame. The handle is not displayed
      // here, so release it and let the cached master hold the pixels.
      unawaited(widget.imageStore
          .load(filePath, RawLayer.fastPreview, priority: TaskPriority.low)
          .then((image) => image?.dispose()));
    } else {
      // For bitmaps, preload the same low-res layer used by single preview
      if (mounted) {
        precacheImage(
          ResizeImage(
            FileImage(File(filePath)),
            width: widget.thumbnailResizeWidth,
          ),
          context,
        );
      }
    }
  }

  void _switchPage(int delta) {
    int newTarget = _targetPage + delta;
    if (newTarget < 0) newTarget = 0;
    if (newTarget >= widget.files.length) newTarget = widget.files.length - 1;

    if (newTarget == _targetPage && newTarget == _currentIndex) {
      return;
    }

    bool isAnimating = false;
    if (_pageController.position.haveDimensions) {
      final page = _pageController.page!;
      if ((page - page.round()).abs() > 0.05) {
        isAnimating = true;
      }
    }

    final now = DateTime.now();
    bool fastScroll = isAnimating ||
        (_lastSwitchTime != null &&
            now.difference(_lastSwitchTime!).inMilliseconds < 400);
    _lastSwitchTime = now;

    _targetPage = newTarget;
    // Preload thumbnails IMMEDIATELY on scroll intention, rather than waiting for animation to hit 50%
    _preloadThumbnails(_targetPage,
        isFastScrolling: fastScroll || _isFastScrolling.value);

    void startFastScrollTimer() {
      _isFastScrolling.value = true;
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _isFastScrolling.value = false;
        // Also ensure we correctly update target/index when stopping
        if (_pageController.page != _targetPage.toDouble()) {
          _pageController.jumpToPage(_targetPage);
        }
      });
    }

    if (fastScroll || _isFastScrolling.value) {
      startFastScrollTimer();
      _pageController.jumpToPage(_targetPage);
    } else {
      _pageController.animateToPage(
        _targetPage,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFilePath = widget.files[_currentIndex].path;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            physics: _isLocked
                ? const NeverScrollableScrollPhysics()
                : const FastPageScrollPhysics(),
            allowImplicitScrolling: true,
            padEnds: true,
            itemCount: widget.files.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final mediaFile = widget.files[index];
              final filePath = mediaFile.path;
              return _SingleImagePreview(
                key: ValueKey(filePath),
                mediaFile: mediaFile,
                thumbnailResizeWidth: widget.thumbnailResizeWidth,
                imageStore: widget.imageStore,
                settings: widget.settings,
                onSwitchRequest: _switchPage,
                isActive: index == _currentIndex,
                isFastScrolling: _isFastScrolling,
                onScaleStateChanged: (isScaling) {
                  if (_isLocked != isScaling) {
                    setState(() {
                      _isLocked = isScaling;
                    });
                  }
                },
              );
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FutureBuilder<_MediaTimestampInfo>(
              future: _currentTimestampFuture,
              builder: (context, snapshot) {
                final timestampText = snapshot.hasData
                    ? snapshot.data!.format(widget.settings.timeDisplaySource)
                    : '---- -- -- --:--:--';
                return AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(path.basename(currentFilePath)),
                      Text(
                        timestampText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onClose,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleImagePreview extends StatefulWidget {
  final _MediaFile mediaFile;
  final int thumbnailResizeWidth;
  final ImageStore imageStore;
  final ViewerSettings settings;
  final Function(int) onSwitchRequest;
  final bool isActive;
  final ValueNotifier<bool> isFastScrolling;
  final ValueChanged<bool>? onScaleStateChanged;

  const _SingleImagePreview({
    super.key,
    required this.mediaFile,
    required this.thumbnailResizeWidth,
    required this.imageStore,
    required this.settings,
    required this.onSwitchRequest,
    required this.isActive,
    required this.isFastScrolling,
    this.onScaleStateChanged,
  });

  String get filePath => mediaFile.path;
  bool get isRaw => mediaFile.isRaw;

  @override
  State<_SingleImagePreview> createState() => _SingleImagePreviewState();
}

class _SingleImagePreviewState extends State<_SingleImagePreview> {
  ViewerImage? _fastPreviewImage;
  ViewerImage? _decodedRawPreviewImage;
  bool _isLoadingDecodedRawPreview = false;
  late bool _preferFastPreviewForRaw;
  late int _rawDecodeHalfSize;
  final TransformationController _transformationController =
      TransformationController();
  bool _panEnabled = false;
  // InteractiveViewer scaleEnabled defaults to true.
  // We want to disable it for Mouse (to prevent default zoom on scroll)
  // but keep it enabled for Touch (pinch zoom).
  bool _scaleEnabled = false;
  final Set<int> _activePointers = {};

  /// Only the expensive decoded-RAW task is tracked for cancellation.
  ///
  /// The fast preview is deliberately never cancelled: it is cheap, and the
  /// worker dedupes it by path, so cancelling ours would also resolve a grid
  /// tile's shared request to null and leave that tile showing a broken image.
  WorkerTask<LibRawImage?>? _decodedRawTask;

  @override
  void initState() {
    super.initState();
    _preferFastPreviewForRaw = widget.settings.preferFastPreviewForRaw;
    _rawDecodeHalfSize = widget.settings.useHalfSizeRawDecode ? 1 : 0;

    // Take a cached fast preview synchronously so the first frame of a page
    // switch already paints an image instead of an empty (black) area. Prefer
    // the full-resolution entry, but fall back to the grid's thumbnail-sized
    // one: showing it slightly soft for a moment beats showing black.
    if (widget.isRaw) {
      _fastPreviewImage =
          widget.imageStore.peek(widget.filePath, RawLayer.fastPreview) ??
              widget.imageStore.peek(widget.filePath, RawLayer.fastPreview,
                  targetWidth: widget.thumbnailResizeWidth);
    }

    unawaited(_loadRawDisplayLayers());
    _transformationController.addListener(_onTransformationChange);
    widget.isFastScrolling.addListener(_onFastScrollingChanged);
  }

  @override
  void didUpdateWidget(_SingleImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isFastScrolling != widget.isFastScrolling) {
      oldWidget.isFastScrolling.removeListener(_onFastScrollingChanged);
      widget.isFastScrolling.addListener(_onFastScrollingChanged);
    }

    if (!widget.isActive && oldWidget.isActive) {
      _transformationController.value = Matrix4.identity();
      _cancelDecodedRawTask();
    }

    if (widget.isActive && !oldWidget.isActive) {
      // Reload skips whatever layer is already available.
      unawaited(_loadRawDisplayLayers());
    }
  }

  @override
  void dispose() {
    widget.isFastScrolling.removeListener(_onFastScrollingChanged);
    _decodedRawTask?.cancel();
    _fastPreviewImage?.dispose();
    _decodedRawPreviewImage?.dispose();
    _transformationController.removeListener(_onTransformationChange);
    _transformationController.dispose();
    super.dispose();
  }

  void _cancelDecodedRawTask() {
    _decodedRawTask?.cancel();
    _decodedRawTask = null;
    if (_isLoadingDecodedRawPreview && mounted) {
      setState(() {
        _isLoadingDecodedRawPreview = false;
      });
    } else {
      _isLoadingDecodedRawPreview = false;
    }
  }

  void _onFastScrollingChanged() {
    if (!widget.isActive) return;

    if (widget.isFastScrolling.value) {
      // Do not spend CPU on a full decode the user is scrolling straight past.
      _cancelDecodedRawTask();
    } else {
      unawaited(_loadRawDisplayLayers());
    }
  }

  void _onTransformationChange() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final newPanEnabled = scale > 1.01; // Small epsilon
    if (_panEnabled != newPanEnabled) {
      setState(() {
        _panEnabled = newPanEnabled;
      });
    }
  }

  Future<void> _loadRawDisplayLayers() async {
    // For non-RAW files, we rely entirely on Flutter's Image.file
    if (!widget.isRaw) return;

    if (_fastPreviewImage == null) {
      // If not active, or fast scrolling, use low priority
      final fastPreviewPriority =
          (!widget.isActive || widget.isFastScrolling.value)
              ? TaskPriority.low
              : TaskPriority.high;

      // No targetWidth: this is the full-screen layer, so keep the preview's
      // own resolution rather than the grid's thumbnail size.
      final fastPreviewImage = await widget.imageStore.load(
        widget.filePath,
        RawLayer.fastPreview,
        priority: fastPreviewPriority,
      );

      if (!mounted) {
        fastPreviewImage?.dispose();
        return;
      }

      if (fastPreviewImage != null) {
        setState(() {
          _fastPreviewImage?.dispose();
          _fastPreviewImage = fastPreviewImage;
        });
      }
    }

    if (!widget.isActive || widget.isFastScrolling.value) {
      return;
    }

    if (_preferFastPreviewForRaw) return;
    if (_decodedRawPreviewImage != null) return;

    setState(() {
      _isLoadingDecodedRawPreview = true;
    });

    final decodedRawPreviewImage = await widget.imageStore.load(
      widget.filePath,
      RawLayer.decoded,
      halfSize: _rawDecodeHalfSize,
      onTaskStarted: (task) => _decodedRawTask = task,
    );
    _decodedRawTask = null;

    // A cancelled or superseded load must not overwrite what is on screen.
    if (!mounted || !widget.isActive || _preferFastPreviewForRaw) {
      decodedRawPreviewImage?.dispose();
      if (mounted && _isLoadingDecodedRawPreview) {
        setState(() {
          _isLoadingDecodedRawPreview = false;
        });
      }
      return;
    }

    setState(() {
      if (decodedRawPreviewImage != null) {
        _decodedRawPreviewImage?.dispose();
        _decodedRawPreviewImage = decodedRawPreviewImage;
      }
      _isLoadingDecodedRawPreview = false;
    });
  }

  void _toggleRawPreviewSource() {
    if (!widget.isRaw) return;

    final nextPreferFastPreviewForRaw = !_preferFastPreviewForRaw;
    if (nextPreferFastPreviewForRaw && _fastPreviewImage != null) {
      // Switching to the fast preview: abandon the full decode in flight.
      _decodedRawTask?.cancel();
      _decodedRawTask = null;
    }
    setState(() {
      _preferFastPreviewForRaw = nextPreferFastPreviewForRaw;
      if (_preferFastPreviewForRaw) {
        _isLoadingDecodedRawPreview = false;
      }
    });
    if (!_preferFastPreviewForRaw && _decodedRawPreviewImage == null) {
      unawaited(_loadRawDisplayLayers());
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
      final isCtrlPressed =
          keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
              keysPressed.contains(LogicalKeyboardKey.controlRight);
      final isMetaPressed = keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
          keysPressed.contains(LogicalKeyboardKey.metaRight);
      final isZoomModifierPressed =
          Platform.isMacOS ? (isMetaPressed || isCtrlPressed) : isCtrlPressed;

      if (isZoomModifierPressed) {
        // Zoom centered on mouse pointer
        final double scaleChange = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
        final Offset focalPoint = event.localPosition;

        final Matrix4 matrix = _transformationController.value.clone();

        final Matrix4 scaleMatrix = Matrix4.identity()
          ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
          ..scaleByDouble(scaleChange, scaleChange, scaleChange, 1)
          ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);

        final Matrix4 newMatrix = scaleMatrix * matrix;

        _transformationController.value = newMatrix;
      } else {
        // Switch image
        if (event.scrollDelta.dy > 0) {
          widget.onSwitchRequest(1);
        } else if (event.scrollDelta.dy < 0) {
          widget.onSwitchRequest(-1);
        }
      }
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _checkPointers();
    // If touch, enable scaling (pinch)
    if (event.kind == PointerDeviceKind.touch) {
      if (!_scaleEnabled) {
        setState(() {
          _scaleEnabled = true;
        });
      }
    } else if (event.kind == PointerDeviceKind.mouse) {
      if (_scaleEnabled) {
        setState(() {
          _scaleEnabled = false;
        });
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _checkPointers();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _checkPointers();
  }

  void _checkPointers() {
    final shouldLock = _activePointers.length >= 2;
    widget.onScaleStateChanged?.call(shouldLock);
  }

  void _onPointerHover(PointerHoverEvent event) {
    // If mouse hover, disable scaling to prevent wheel zoom
    if (event.kind == PointerDeviceKind.mouse && _scaleEnabled) {
      setState(() {
        _scaleEnabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Stack(
      children: [
        Listener(
          onPointerSignal: _handlePointerSignal,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          onPointerHover: _onPointerHover,
          child: Center(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0, // Prevent zooming out smaller than screen
              maxScale: 5.0,
              panEnabled: _panEnabled,
              scaleEnabled: _scaleEnabled,
              child: widget.isRaw
                  ? _buildRawPreview()
                  : Stack(
                      fit: StackFit.expand,
                      children: [_buildBitmapPreview()],
                    ),
            ),
          ),
        ),
        // Overlay controls
        Positioned(
          top: kToolbarHeight + 20, // Below the main AppBar
          right: 10,
          child: TextButton(
            onPressed: _toggleRawPreviewSource,
            style: TextButton.styleFrom(backgroundColor: Colors.black54),
            child: Text(
              widget.isRaw
                  ? (_preferFastPreviewForRaw
                      ? l10n.fastPreviewShortLabel
                      : l10n.rawShortLabel)
                  : l10n.imageShortLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Paints exactly one RAW image layer.
  ///
  /// The decoded layer fully covers the fast preview, so stacking both would
  /// pay for a large overdraw every frame with nothing to show for it. The
  /// spinner only appears when there is genuinely nothing to display yet.
  Widget _buildRawPreview() {
    final showDecoded =
        _decodedRawPreviewImage != null && !_preferFastPreviewForRaw;
    final displayed = showDecoded ? _decodedRawPreviewImage : _fastPreviewImage;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (displayed != null)
          RawImageWidget(
            image: displayed,
            fit: BoxFit.contain,
            heroTag: widget.isActive ? widget.filePath : null,
          ),
        if (displayed == null)
          const Center(
            child: ExcludeSemantics(child: CircularProgressIndicator()),
          )
        else if (_isLoadingDecodedRawPreview && !showDecoded)
          // Sharpening in the background; keep showing the fast preview.
          const Positioned(
            top: kToolbarHeight + 24,
            left: 16,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBitmapPreview() {
    final file = File(widget.filePath);

    // Decoding a bitmap at full resolution costs width*height*4 bytes no matter
    // how small the window is — an 8000x6000 JPEG is ~192 MB. Cap the decode at
    // what the viewport can actually show, with headroom for zooming in.
    final mediaQuery = MediaQuery.of(context);
    final viewportWidth = mediaQuery.size.width * mediaQuery.devicePixelRatio;
    final fullDecodeWidth = bucketDecodeWidth(
      (viewportWidth * _bitmapZoomHeadroom).clamp(
        widget.thumbnailResizeWidth.toDouble(),
        _maxBitmapDecodeWidth,
      ),
    );

    Widget image = ValueListenableBuilder<bool>(
      valueListenable: widget.isFastScrolling,
      builder: (context, isFastScrolling, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage(
                FileImage(file),
                width: widget.thumbnailResizeWidth,
              ),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
            if (widget.isActive && !isFastScrolling)
              Image(
                image: ResizeImage(
                  FileImage(file),
                  width: fullDecodeWidth,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );

    // Only wrap the active image in a Hero to prevent duplicate Hero tags in the PageView
    if (widget.isActive) {
      return Hero(tag: widget.filePath, child: image);
    }
    return image;
  }
}

/// Extra resolution decoded beyond the viewport so zooming stays sharp.
const double _bitmapZoomHeadroom = 2.0;

/// Hard ceiling on bitmap decode width, in physical pixels.
const double _maxBitmapDecodeWidth = 4096;

/// Paints an already-decoded [ViewerImage].
///
/// Uses [RawImage] rather than [Image.memory] on purpose: the `ui.Image` is
/// already in hand, so the pixels land in the very frame this widget is built.
/// Going through `Image.memory` would re-enter the async codec path and leave a
/// blank (black, over the dark scaffold) gap on every page switch.
class RawImageWidget extends StatelessWidget {
  final ViewerImage image;
  final BoxFit? fit;
  final String? heroTag;

  const RawImageWidget({
    super.key,
    required this.image,
    this.fit,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget painted = RawImage(
      image: image.image,
      fit: fit,
      filterQuality: FilterQuality.medium,
    );

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: painted,
      );
    }
    return painted;
  }
}

class FastPageScrollPhysics extends PageScrollPhysics {
  const FastPageScrollPhysics({super.parent});

  @override
  FastPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 500.0,
        ratio: 1.0,
      );
}
