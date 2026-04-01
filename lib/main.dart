import 'dart:async';
import 'dart:io';
import 'package:exif/exif.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'l10n/app_localizations.dart';
import 'native_lib.dart';
import 'settings_page.dart';
import 'lru_cache.dart';
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
  final Map<String, Future<_MediaTimestampInfo>> _futureCache = {};

  Future<_MediaTimestampInfo> load(String filePath) {
    return _futureCache.putIfAbsent(
        filePath, () => _readTimestampInfo(filePath));
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

Future<DateTime?> _parseCapturedAtFromBytes(Uint8List bytes) async {
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

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowResized() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) return;

    final size = await windowManager.getSize();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_width', size.width);
    await prefs.setDouble('window_height', size.height);
  }

  @override
  void onWindowMoved() async {
    final isMaximized = await windowManager.isMaximized();
    if (isMaximized) return;

    final position = await windowManager.getPosition();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('window_x', position.dx);
    await prefs.setDouble('window_y', position.dy);
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
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.blue,
          fontFamily: 'NotoSansSC',
        ),
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
  final _TimestampRepository _timestampRepository = _TimestampRepository();
  ViewerSettings _settings = const ViewerSettings();
  int _crossAxisCount = 4;

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
    setState(() {
      _crossAxisCount = prefs.getInt('grid_cross_axis_count') ?? 4;
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

  void _initCache() {
    // maxCacheSize is in MB, convert to bytes
    final int maxBytes = _settings.maxCacheSize * 1024 * 1024;
    _imageCache = LruCache(
      maxBytes,
      sizeOf: (image) => image.data.length,
    );
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Calculate dynamic thumbnail resize width based on grid cell size
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final screenWidth = MediaQuery.of(context).size.width;
    final totalPadding = 16.0 + (_crossAxisCount - 1) * 8.0;
    final cellWidth = (screenWidth - totalPadding) / _crossAxisCount;
    final thumbnailResizeWidth = (cellWidth * dpr).clamp(100.0, 800.0).toInt();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncWindowsContextMenuLanguage(
        l10n.windowsContextMenuMenuText,
      ));
    });

    return Scaffold(
        appBar: AppBar(
          title: Text(_currentTitle(l10n)),
          actions: [
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: 'Zoom In',
              onPressed:
                  _crossAxisCount > 1 ? () => _updateCrossAxisCount(-1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.zoom_out),
              tooltip: 'Zoom Out',
              onPressed:
                  _crossAxisCount < 10 ? () => _updateCrossAxisCount(1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await _refreshWindowsContextMenuState();
                if (!mounted || !context.mounted) {
                  return;
                }

                final result = await Navigator.push<ViewerSettings>(
                  context,
                  PageRouteBuilder(
                    opaque: false,
                    barrierColor: Colors.black54,
                    barrierDismissible: true,
                    pageBuilder: (context, animation, secondaryAnimation) {
                      return ExcludeSemantics(
                        child: FadeTransition(
                          opacity: animation,
                          child: Center(
                            child: Container(
                                width: 500,
                                height: 600,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: SettingsPage(
                                  settings: _settings,
                                  onWindowsContextMenuChanged:
                                      Platform.isWindows
                                          ? _setWindowsContextMenuEnabled
                                          : null,
                                  onClose: (res) {
                                    Navigator.pop(context, res);
                                  },
                                )),
                          ),
                        ),
                      );
                    },
                  ),
                );

                if (result != null) {
                  widget.onAppLanguageChanged(result.appLanguage);
                  setState(() {
                    if (_settings.maxCacheSize != result.maxCacheSize) {
                      _settings = result;
                      _initCache(); // Re-initialize with new size
                    } else {
                      _settings = result;
                    }
                  });
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.file_open),
              onPressed: _openFiles,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              onPressed: _openFolder,
            ),
          ],
        ),
        body: ExcludeSemantics(
          child: _files.isEmpty
              ? Center(
                  child: Text(l10n.homeEmptyState),
                )
              : GridView.builder(
                  addAutomaticKeepAlives: false,
                  cacheExtent: 200,
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _crossAxisCount,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final mediaFile = _files[index];
                    final filePath = mediaFile.path;
                    final fastPreviewCacheKey = '$filePath:fast-preview';
                    return MediaThumbnailTile(
                      key: ValueKey(filePath),
                      mediaFile: mediaFile,
                      settings: _settings,
                      timestampRepository: _timestampRepository,
                      resizeWidth: thumbnailResizeWidth,
                      cachedFastPreviewImage: mediaFile.isRaw
                          ? _imageCache.get(fastPreviewCacheKey)
                          : null,
                      onFastPreviewCacheUpdate: (image) {
                        if (mediaFile.isRaw) {
                          Future(
                            () => _imageCache.put(fastPreviewCacheKey, image),
                          );
                        }
                      },
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) {
                              return ExcludeSemantics(
                                child: FadeTransition(
                                  opacity: animation,
                                  child: ImagePreviewPage(
                                    files: _files,
                                    initialIndex: index,
                                    thumbnailResizeWidth: thumbnailResizeWidth,
                                    imageCache: _imageCache,
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
                  },
                ),
        ));
  }
}

class MediaThumbnailTile extends StatefulWidget {
  final _MediaFile mediaFile;
  final ViewerSettings settings;
  final _TimestampRepository timestampRepository;
  final int resizeWidth;
  final ViewerImage? cachedFastPreviewImage;
  final Function(ViewerImage) onFastPreviewCacheUpdate;
  final VoidCallback onTap;

  const MediaThumbnailTile({
    super.key,
    required this.mediaFile,
    required this.settings,
    required this.timestampRepository,
    required this.resizeWidth,
    this.cachedFastPreviewImage,
    required this.onFastPreviewCacheUpdate,
    required this.onTap,
  });

  String get filePath => mediaFile.path;

  @override
  State<MediaThumbnailTile> createState() => _MediaThumbnailTileState();
}

class _MediaThumbnailTileState extends State<MediaThumbnailTile> {
  WorkerTask<LibRawImage?>? _fastPreviewTask;
  Future<ViewerImage?>? _fastPreviewFuture;
  late Future<_MediaTimestampInfo> _timestampFuture;

  @override
  void initState() {
    super.initState();
    // Start loading only if not cached (RAW files only; bitmaps use FileImage)
    if (widget.mediaFile.isRaw && widget.cachedFastPreviewImage == null) {
      _loadRawFastPreview();
    }
    _timestampFuture = widget.timestampRepository.load(widget.filePath);
  }

  @override
  void didUpdateWidget(MediaThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath) {
      _fastPreviewTask?.cancel();
      _fastPreviewTask = null;
      _fastPreviewFuture = null;

      // If the file path changes (recycling), we need to reload or check cache
      if (widget.mediaFile.isRaw && widget.cachedFastPreviewImage == null) {
        _loadRawFastPreview();
      }
      _timestampFuture = widget.timestampRepository.load(widget.filePath);
    } else if (widget.settings.timeDisplaySource !=
        oldWidget.settings.timeDisplaySource) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _fastPreviewTask?.cancel();
    super.dispose();
  }

  void _loadRawFastPreview() {
    // Only called for RAW files; bitmap files use FileImage directly.
    // This layer prefers embedded preview data and falls back to a fast
    // RAW-generated preview when the file has no embedded preview.
    final task = WorkerService().requestRawFastPreview(widget.filePath);
    _fastPreviewTask = task;
    _fastPreviewFuture = task.result.then((image) {
      if (!mounted) return null;
      if (image == null) {
        return null;
      }
      final viewerImage = ViewerImage.fromRaw(image);
      widget.onFastPreviewCacheUpdate(viewerImage);
      return viewerImage;
    });
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
          child: GridTile(
            footer: Container(
              color: Colors.black45,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    path.basename(widget.filePath),
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.05,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                          fontSize: 9,
                          height: 1.0,
                          color: Colors.white70,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(),
                if (widget.mediaFile.isRaw)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.rawShortLabel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
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

    // RAW files: show the cached fast preview layer if we already have it.
    if (widget.cachedFastPreviewImage != null) {
      return RawImageWidget(
        image: widget.cachedFastPreviewImage!,
        fit: BoxFit.cover,
        memCacheWidth: widget.resizeWidth,
        heroTag: widget.filePath,
      );
    }

    return FutureBuilder<ViewerImage?>(
      future: _fastPreviewFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            color: Colors.grey[800],
            child: const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
          return Container(
            color: Colors.grey[800],
            child: const Center(child: Icon(Icons.broken_image, size: 20)),
          );
        }

        return RawImageWidget(
          image: snapshot.data!,
          fit: BoxFit.cover,
          memCacheWidth: widget.resizeWidth,
          heroTag: widget.filePath,
        );
      },
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

class ImagePreviewPage extends StatefulWidget {
  final List<_MediaFile> files;
  final int initialIndex;
  final int thumbnailResizeWidth;
  final LruCache<String, ViewerImage> imageCache;
  final _TimestampRepository timestampRepository;
  final ViewerSettings settings;
  final VoidCallback onClose;

  const ImagePreviewPage({
    super.key,
    required this.files,
    required this.initialIndex,
    required this.thumbnailResizeWidth,
    required this.imageCache,
    required this.timestampRepository,
    required this.settings,
    required this.onClose,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late PageController _pageController;
  late int _currentIndex;
  late int _targetPage;
  bool _isLocked = false;

  DateTime? _lastSwitchTime;
  Timer? _scrollStopTimer;
  bool _isFastScrolling = false;
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
    if (index >= 0 && index < widget.files.length) {
      final mediaFile = widget.files[index];
      final String filePath = mediaFile.path;
      final fastPreviewCacheKey = '$filePath:fast-preview';

      if (mediaFile.isRaw) {
        if (widget.imageCache.get(fastPreviewCacheKey) == null) {
          WorkerService()
              .requestRawFastPreview(filePath, priority: TaskPriority.low)
              .result
              .then((fastPreviewImage) {
            if (fastPreviewImage != null && mounted) {
              widget.imageCache.put(
                fastPreviewCacheKey,
                ViewerImage.fromRaw(fastPreviewImage),
              );
            }
          });
        }
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
        isFastScrolling: fastScroll || _isFastScrolling);

    void startFastScrollTimer() {
      if (!_isFastScrolling) {
        setState(() {
          _isFastScrolling = true;
        });
      }
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _isFastScrolling = false;
            // Also ensure we correctly update target/index when stopping
            if (_pageController.page != _targetPage.toDouble()) {
              _pageController.jumpToPage(_targetPage);
            }
          });
        }
      });
    }

    if (fastScroll || _isFastScrolling) {
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
              return SingleImagePreview(
                key: ValueKey(filePath),
                mediaFile: mediaFile,
                fastPreviewImage:
                    widget.imageCache.get('$filePath:fast-preview'),
                thumbnailResizeWidth: widget.thumbnailResizeWidth,
                imageCache: widget.imageCache,
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

class SingleImagePreview extends StatefulWidget {
  final _MediaFile mediaFile;
  final ViewerImage? fastPreviewImage;
  final int thumbnailResizeWidth;
  final LruCache<String, ViewerImage> imageCache;
  final ViewerSettings settings;
  final Function(int) onSwitchRequest;
  final bool isActive;
  final bool isFastScrolling;
  final ValueChanged<bool>? onScaleStateChanged;

  const SingleImagePreview({
    super.key,
    required this.mediaFile,
    this.fastPreviewImage,
    required this.thumbnailResizeWidth,
    required this.imageCache,
    required this.settings,
    required this.onSwitchRequest,
    required this.isActive,
    required this.isFastScrolling,
    this.onScaleStateChanged,
  });

  String get filePath => mediaFile.path;
  bool get isRaw => mediaFile.isRaw;

  @override
  State<SingleImagePreview> createState() => _SingleImagePreviewState();
}

class _SingleImagePreviewState extends State<SingleImagePreview> {
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

  @override
  void initState() {
    super.initState();
    _fastPreviewImage = widget.fastPreviewImage;
    _preferFastPreviewForRaw = widget.settings.preferFastPreviewForRaw;
    _rawDecodeHalfSize = widget.settings.useHalfSizeRawDecode ? 1 : 0;
    _loadRawDisplayLayers();
    _transformationController.addListener(_onTransformationChange);
  }

  @override
  void didUpdateWidget(SingleImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && oldWidget.isActive) {
      _transformationController.value = Matrix4.identity();
      if (_currentTask != null) {
        _currentTask!.cancel();
        _currentTask = null;
        if (mounted) {
          setState(() {
            _isLoadingDecodedRawPreview = false;
          });
        }
      }
    }

    bool becameActive = widget.isActive && !oldWidget.isActive;
    bool fastScrollStopped =
        widget.isActive && !widget.isFastScrolling && oldWidget.isFastScrolling;
    bool fastScrollStarted =
        widget.isActive && widget.isFastScrolling && !oldWidget.isFastScrolling;

    if (becameActive || fastScrollStopped || fastScrollStarted) {
      // Cancel any ongoing task to restart with correct priority
      _currentTask?.cancel();
      _currentTask = null;
      _isLoadingDecodedRawPreview = false;

      // Reload logic will skip if the fast preview or decoded RAW layer is
      // already available.
      _loadRawDisplayLayers();
    }
  }

  WorkerTask<LibRawImage?>? _currentTask;

  @override
  void dispose() {
    _currentTask?.cancel();
    _transformationController.removeListener(_onTransformationChange);
    _transformationController.dispose();
    super.dispose();
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
      // Check whether the RAW fast preview layer is already in cache.
      final fastPreviewKey = '${widget.filePath}:fast-preview';
      final cachedFastPreview = widget.imageCache.get(fastPreviewKey);

      if (cachedFastPreview != null) {
        if (mounted) {
          setState(() {
            _fastPreviewImage = cachedFastPreview;
          });
        }
      } else {
        // If not active, or fast scrolling, use low priority
        final fastPreviewPriority =
            (!widget.isActive || widget.isFastScrolling)
            ? TaskPriority.low
            : TaskPriority.high;
        ViewerImage? fastPreviewImage;
        if (widget.isRaw) {
          final task = WorkerService()
              .requestRawFastPreview(widget.filePath,
                  priority: fastPreviewPriority);
          _currentTask = task;
          final rawFastPreview = await task.result;
          _currentTask = null;
          if (rawFastPreview != null) {
            fastPreviewImage = ViewerImage.fromRaw(rawFastPreview);
          }
        }

        if (mounted && fastPreviewImage != null) {
          setState(() {
            _fastPreviewImage = fastPreviewImage;
          });
          // Cache it for fast subsequent switches.
          Future(() => widget.imageCache.put(fastPreviewKey, fastPreviewImage!));
        }
      }
    }

    if (!widget.isActive || widget.isFastScrolling) {
      if (widget.isFastScrolling &&
          _currentTask != null &&
          _fastPreviewImage != null) {
        _currentTask?.cancel();
        _currentTask = null;
        if (mounted) {
          setState(() {
            _isLoadingDecodedRawPreview = false;
          });
        }
      }
      return;
    }

    if (_preferFastPreviewForRaw) return;
    if (_decodedRawPreviewImage != null) return;

    // Check cache for the decoded RAW layer.
    final decodedRawPreviewKey =
        '${widget.filePath}:decoded-raw:$_rawDecodeHalfSize';
    final cachedDecodedRawPreview = widget.imageCache.get(decodedRawPreviewKey);
    if (cachedDecodedRawPreview != null) {
      setState(() {
        _decodedRawPreviewImage = cachedDecodedRawPreview;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingDecodedRawPreview = true;
      });
    }

    const priority = TaskPriority.high;
    final task = WorkerService().requestDecodedRawPreview(widget.filePath,
        halfSize: _rawDecodeHalfSize, priority: priority);
    _currentTask = task;
    final rawDecodedRawPreview = await task.result;
    _currentTask = null;
    final decodedRawPreviewImage = rawDecodedRawPreview == null
        ? null
        : ViewerImage.fromRaw(rawDecodedRawPreview);

    if (mounted && widget.isActive) {
      setState(() {
        _decodedRawPreviewImage = decodedRawPreviewImage;
        _isLoadingDecodedRawPreview = false;
      });
      if (decodedRawPreviewImage != null) {
        // Run cache update asynchronously to avoid blocking UI or subsequent tasks.
        Future(() =>
            widget.imageCache.put(decodedRawPreviewKey, decodedRawPreviewImage));
      }
    }
  }

  void _toggleRawPreviewSource() {
    if (!widget.isRaw) return;

    final nextPreferFastPreviewForRaw = !_preferFastPreviewForRaw;
    if (nextPreferFastPreviewForRaw &&
        _currentTask != null &&
        _fastPreviewImage != null) {
      _currentTask?.cancel();
      _currentTask = null;
    }
    setState(() {
      _preferFastPreviewForRaw = nextPreferFastPreviewForRaw;
      if (_preferFastPreviewForRaw) {
        _isLoadingDecodedRawPreview = false;
      }
    });
    if (!_preferFastPreviewForRaw && _decodedRawPreviewImage == null) {
      _loadRawDisplayLayers();
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
          ..translate(focalPoint.dx, focalPoint.dy)
          ..scale(scaleChange)
          ..translate(-focalPoint.dx, -focalPoint.dy);

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (!widget.isRaw)
                    _buildBitmapPreview()
                  else ...[
                    if (_fastPreviewImage != null)
                      // Low-res placeholder from the cached RAW fast preview.
                      RawImageWidget(
                        image: _fastPreviewImage!,
                        fit: BoxFit.contain,
                        memCacheWidth: widget.thumbnailResizeWidth,
                        heroTag: widget.isActive ? widget.filePath : null,
                      ),
                    if (_fastPreviewImage != null && _preferFastPreviewForRaw)
                      // RAW fast preview layer. This usually comes from the
                      // embedded preview, but may fall back to a fast RAW
                      // decode when no embedded preview exists.
                      if (widget.isActive && !widget.isFastScrolling)
                        RawImageWidget(
                          image: _fastPreviewImage!,
                          fit: BoxFit.contain,
                        ),
                    if (_decodedRawPreviewImage != null &&
                        !_preferFastPreviewForRaw &&
                        widget.isActive &&
                        !widget.isFastScrolling)
                      RawImageWidget(
                        image: _decodedRawPreviewImage!,
                        fit: BoxFit.contain,
                      ),
                    if (_fastPreviewImage == null &&
                        (_decodedRawPreviewImage == null ||
                            _preferFastPreviewForRaw))
                      const Center(
                          child: ExcludeSemantics(
                              child: CircularProgressIndicator())),
                    if (_isLoadingDecodedRawPreview &&
                        _decodedRawPreviewImage == null &&
                        !_preferFastPreviewForRaw)
                      const Center(
                          child: ExcludeSemantics(
                        child: CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white54),
                        ),
                      )),
                  ],
                ],
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

  Widget _buildBitmapPreview() {
    final file = File(widget.filePath);
    Widget image = Stack(
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
        if (widget.isActive && !widget.isFastScrolling)
          Image.file(
            file,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white),
            ),
          ),
      ],
    );

    // Only wrap the active image in a Hero to prevent duplicate Hero tags in the PageView
    if (widget.isActive) {
      return Hero(tag: widget.filePath, child: image);
    }
    return image;
  }
}

class RawImageWidget extends StatelessWidget {
  final ViewerImage image;
  final BoxFit? fit;
  final int? memCacheWidth;
  final String? heroTag;

  const RawImageWidget({
    super.key,
    required this.image,
    this.fit,
    this.memCacheWidth,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget image = Image.memory(
      this.image.data,
      fit: fit,
      cacheWidth: memCacheWidth,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const Center(
        child: Icon(Icons.broken_image, color: Colors.white),
      ),
    );

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: image,
      );
    }
    return image;
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
