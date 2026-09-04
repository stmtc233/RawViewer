import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
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
import 'media_group.dart';
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

/// Motion timings for entering and navigating the full-screen image preview.
///
/// These are intentionally brief: the preview should acknowledge a selection
/// or navigation command immediately, while still giving the user spatial
/// feedback that the active image changed.
const Duration kImagePreviewOpenTransitionDuration =
    Duration(milliseconds: 100);
const Duration kImagePreviewCloseTransitionDuration =
    Duration(milliseconds: 80);
const double kImagePreviewToolbarHeight = 52;
const double kPreviewFilmstripHeight = 88;
const double kPreviewFilmstripItemWidth = 88;
const double kPreviewFilmstripItemExtent = 96;
const double kPreviewOverviewMapWidth = 180;
const double kPreviewOverviewMapHeight = 120;
const double _previewImageControlsHeight = 42;
const double _previewOverviewGap = 10;
const Duration kImagePreviewPageSwitchDuration = Duration(milliseconds: 55);
const Duration kImagePreviewRapidSwitchThreshold = Duration(milliseconds: 180);
const Duration kImagePreviewRapidSwitchSettleDelay =
    Duration(milliseconds: 140);
const double _gridZoomScrollStep = 20;
const double _gridZoomLogScaleStep = 0.12;
const double _previewTrackpadScaleSlop = 0.015;
const double _trackpadPageDragSensitivity = 2.5;
const double _trackpadFlingMinVelocity = 350;
const double kMinPreviewScale = 0.25;
const double kMaxPreviewScale = 5.0;
const double _previewFitScale = 1.0;
const double _previewScaleEpsilon = 0.01;
const double _previewControlZoomStep = 1.25;
const Duration _previewFitScaleLockDuration = Duration(milliseconds: 100);

double clampPreviewScale(double scale) {
  return scale.clamp(kMinPreviewScale, kMaxPreviewScale).toDouble();
}

/// Returns the small set of pages shown around the active image in the
/// preview filmstrip.
List<int> previewNavigationIndices({
  required int currentIndex,
  required int itemCount,
  int radius = 2,
}) {
  if (itemCount <= 0) {
    return const [];
  }

  final safeCurrentIndex = currentIndex.clamp(0, itemCount - 1).toInt();
  final safeRadius = radius < 0 ? 0 : radius;
  final first = math.max(0, safeCurrentIndex - safeRadius);
  final last = math.min(itemCount - 1, safeCurrentIndex + safeRadius);
  return [for (var index = first; index <= last; index++) index];
}

/// Maps the visible portion of the zoomed image onto an overview map.
Rect previewOverviewViewportRect({
  required Matrix4 transform,
  required Size viewportSize,
  required Size mapSize,
}) {
  if (viewportSize.isEmpty || mapSize.isEmpty) {
    return Offset.zero & mapSize;
  }

  final scale = transform.getMaxScaleOnAxis();
  if (!scale.isFinite || scale <= 0) {
    return Offset.zero & mapSize;
  }

  final translation = transform.getTranslation();
  final visibleWidth = viewportSize.width / scale;
  final visibleHeight = viewportSize.height / scale;
  final visibleLeft = (-translation.x / scale)
      .clamp(0.0, math.max(0.0, viewportSize.width - visibleWidth))
      .toDouble();
  final visibleTop = (-translation.y / scale)
      .clamp(0.0, math.max(0.0, viewportSize.height - visibleHeight))
      .toDouble();
  final visibleRight =
      (visibleLeft + visibleWidth).clamp(0.0, viewportSize.width).toDouble();
  final visibleBottom =
      (visibleTop + visibleHeight).clamp(0.0, viewportSize.height).toDouble();

  return Rect.fromLTRB(
    visibleLeft / viewportSize.width * mapSize.width,
    visibleTop / viewportSize.height * mapSize.height,
    visibleRight / viewportSize.width * mapSize.width,
    visibleBottom / viewportSize.height * mapSize.height,
  );
}

bool shouldResetPreviewPositionAtFitScale({
  required double currentScale,
  required double targetScale,
}) {
  return (currentScale > _previewFitScale && targetScale <= _previewFitScale) ||
      (currentScale < _previewFitScale && targetScale >= _previewFitScale);
}

enum _PreviewScaleDirection { zoomIn, zoomOut }

bool _isZoomModifierPressed() {
  final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
  final isCtrlPressed = keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
      keysPressed.contains(LogicalKeyboardKey.controlRight);
  if (!Platform.isMacOS) {
    return isCtrlPressed;
  }

  return isCtrlPressed ||
      keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
      keysPressed.contains(LogicalKeyboardKey.metaRight);
}

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
  List<MediaFile> _files = [];
  _OpenedSourceKind _openedSourceKind = _OpenedSourceKind.none;
  // Use LRU Cache to limit memory usage.
  late LruCache<String, ViewerImage> _imageCache;
  late ImageStore _imageStore;
  final _TimestampRepository _timestampRepository = _TimestampRepository();
  ViewerSettings _settings = const ViewerSettings();
  MediaFilter _mediaFilter = defaultMediaFilter;
  int _crossAxisCount = 4;
  bool _hasUserConfiguredGridAspectRatio = false;
  double _gridZoomScrollRemainder = 0;
  double _gridZoomLogScaleRemainder = 0;
  double _lastGridTrackpadScale = 1;
  Timer? _gridZoomResetTimer;
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

  @override
  void dispose() {
    _gridZoomResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedGridAspectRatio = GridAspectRatio.values
        .asNameMap()[prefs.getString('grid_aspect_ratio')];
    final pageSwitchAnimationEnabled =
        prefs.getBool('page_switch_animation_enabled') ?? true;
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
      _settings = _settings.copyWith(
        pageSwitchAnimationEnabled: pageSwitchAnimationEnabled,
      );
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

  void _handleGridPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_isZoomModifierPressed()) {
      return;
    }

    final delta = event.scrollDelta.dy;
    if (delta == 0) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      event.respond(allowPlatformDefault: false);
      _updateGridColumnsFromScrollDelta(
        (event as PointerScrollEvent).scrollDelta.dy,
      );
    });
  }

  void _updateGridColumnsFromScrollDelta(double delta) {
    _gridZoomScrollRemainder += delta;
    _gridZoomResetTimer?.cancel();
    _gridZoomResetTimer = Timer(const Duration(milliseconds: 160), () {
      _gridZoomScrollRemainder = 0;
    });

    var columnChange = 0;
    while (_gridZoomScrollRemainder.abs() >= _gridZoomScrollStep) {
      final direction = _gridZoomScrollRemainder.isNegative ? -1 : 1;
      columnChange += direction;
      _gridZoomScrollRemainder -= direction * _gridZoomScrollStep;
    }
    if (columnChange != 0) {
      unawaited(_updateCrossAxisCount(columnChange));
    }
  }

  void _handleGridTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _lastGridTrackpadScale = 1;
    _gridZoomLogScaleRemainder = 0;
  }

  void _handleGridTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale <= 0 || !event.scale.isFinite) {
      return;
    }

    final scaleChange = event.scale / _lastGridTrackpadScale;
    _lastGridTrackpadScale = event.scale;
    if (scaleChange <= 0 || !scaleChange.isFinite) {
      return;
    }

    _gridZoomLogScaleRemainder += math.log(scaleChange);
    var columnChange = 0;
    while (_gridZoomLogScaleRemainder.abs() >= _gridZoomLogScaleStep) {
      // Opening the pinch increases thumbnail size, so reduce the column count.
      final direction = _gridZoomLogScaleRemainder.isNegative ? 1 : -1;
      columnChange += direction;
      _gridZoomLogScaleRemainder += direction * _gridZoomLogScaleStep;
    }
    if (columnChange != 0) {
      unawaited(_updateCrossAxisCount(columnChange));
    }
  }

  Future<void> _persistGridAspectRatio(GridAspectRatio ratio) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('grid_aspect_ratio', ratio.name);
  }

  Future<void> _persistPageSwitchAnimationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('page_switch_animation_enabled', enabled);
  }

  void _updateSettings(ViewerSettings settings) {
    final cacheSizeChanged = _settings.maxCacheSize != settings.maxCacheSize;
    final appLanguageChanged = _settings.appLanguage != settings.appLanguage;
    final gridAspectRatioChanged =
        _settings.gridAspectRatio != settings.gridAspectRatio;
    final pageSwitchAnimationChanged = _settings.pageSwitchAnimationEnabled !=
        settings.pageSwitchAnimationEnabled;

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
    if (pageSwitchAnimationChanged) {
      unawaited(
        _persistPageSwitchAnimationEnabled(
          settings.pageSwitchAnimationEnabled,
        ),
      );
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

    final selectedDirectory = await FilePicker.getDirectoryPath();

    if (selectedDirectory != null) {
      await _handleIncomingPaths([selectedDirectory]);
    }
  }

  Future<void> _openFiles() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _supportedExtensions
          .map((extension) => extension.replaceFirst('.', ''))
          .toList(),
    );

    final selectedFiles =
        result.map((file) => file.path).whereType<String>().toList();
    if (selectedFiles.isEmpty) {
      return;
    }

    await _handleIncomingPaths(selectedFiles);
  }

  String? _currentFolderPath() {
    if (_openedSourceKind == _OpenedSourceKind.folder) {
      return _currentDirectoryPath;
    }

    final directories =
        _files.map((file) => path.normalize(path.dirname(file.path))).toSet();
    return directories.length == 1 ? directories.single : null;
  }

  Future<void> _openCurrentFolder(String folderPath) async {
    final executable = switch (Platform.operatingSystem) {
      'macos' => 'open',
      'windows' => 'explorer.exe',
      'linux' => 'xdg-open',
      _ => null,
    };
    if (executable == null) {
      return;
    }

    try {
      await Process.start(
        executable,
        [folderPath],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // The desktop file manager may be unavailable in a sandboxed session.
    }
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
    final files = <MediaFile>[];

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
    required List<MediaFile> files,
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

  List<MediaFile> _listRawFilesInDirectory(String directoryPath) {
    final files = Directory(directoryPath)
        .listSync()
        .whereType<File>()
        .map((file) => _mediaFileFromPath(file.path))
        .whereType<MediaFile>()
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  List<MediaFile> _deduplicateMediaFiles(Iterable<MediaFile> files) {
    final seen = <String>{};
    final result = <MediaFile>[];

    for (final mediaFile in files) {
      final normalizedPath = path.normalize(path.absolute(mediaFile.path));
      if (seen.add(normalizedPath)) {
        result.add(MediaFile(path: normalizedPath, kind: mediaFile.kind));
      }
    }

    return result;
  }

  MediaFile? _mediaFileFromPath(String filePath) {
    final normalizedPath = path.normalize(path.absolute(filePath));
    final extension = path.extension(normalizedPath).toLowerCase();
    if (_rawExtensions.contains(extension)) {
      return MediaFile(path: normalizedPath, kind: MediaKind.raw);
    }
    if (_bitmapExtensions.contains(extension)) {
      return MediaFile(path: normalizedPath, kind: MediaKind.bitmap);
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

  String _currentFolderActionLabel(AppLocalizations l10n) {
    if (Platform.isMacOS) {
      return l10n.openInFinder;
    }
    if (Platform.isWindows) {
      return l10n.openInExplorer;
    }
    return l10n.openInFileManager;
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
    List<MediaGroup> mediaGroups,
    int index,
    int thumbnailResizeWidth,
  ) {
    final mediaGroup = mediaGroups[index];
    final mediaFile = mediaGroup.primary;
    final filePath = mediaFile.path;
    return _MediaThumbnailTile(
      key: ValueKey(filePath),
      mediaFile: mediaFile,
      hasPairedJpeg: mediaGroup.hasPairedJpeg,
      settings: _settings,
      timestampRepository: _timestampRepository,
      resizeWidth: thumbnailResizeWidth,
      imageStore: _imageStore,
      onAspectRatioChanged: _settings.gridAspectRatio.isAdaptive
          ? (ratio) => _updateMediaAspectRatio(filePath, ratio)
          : null,
      onTap: () {
        Navigator.push<void>(
          context,
          PageRouteBuilder(
            transitionDuration: kImagePreviewOpenTransitionDuration,
            reverseTransitionDuration: kImagePreviewCloseTransitionDuration,
            pageBuilder: (context, animation, secondaryAnimation) {
              return ExcludeSemantics(
                child: _ImagePreviewPage(
                  mediaGroups: mediaGroups,
                  initialIndex: index,
                  thumbnailResizeWidth: thumbnailResizeWidth,
                  imageStore: _imageStore,
                  timestampRepository: _timestampRepository,
                  settings: _settings,
                  onClose: () {
                    Navigator.pop(context);
                  },
                ),
              );
            },
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
                child: child,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildAdaptiveGrid(
    List<MediaGroup> mediaGroups,
    int thumbnailResizeWidth,
  ) {
    const gridPadding = EdgeInsets.fromLTRB(12, 12, 12, 88);
    const gridSpacing = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            math.max(0.0, constraints.maxWidth - gridPadding.horizontal);
        final nominalCellWidth =
            (width - gridSpacing * (_crossAxisCount - 1)) / _crossAxisCount;
        final targetRowHeight = nominalCellWidth / (3 / 2);
        final rows = buildJustifiedGridRows(
          aspectRatios: mediaGroups
              .map(
                (mediaGroup) =>
                    _mediaAspectRatios[mediaGroup.primary.path] ??
                    GridAspectRatio.adaptive.aspectRatio,
              )
              .toList(growable: false),
          availableWidth: width,
          targetRowHeight: targetRowHeight,
          spacing: gridSpacing,
          maxFinalRowHeight: targetRowHeight * 1.5,
        );

        return CustomScrollView(
          scrollCacheExtent: const ScrollCacheExtent.pixels(200),
          slivers: [
            SliverPadding(
              padding: gridPadding,
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, rowIndex) {
                  final row = rows[rowIndex];
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: rowIndex == rows.length - 1 ? 0 : gridSpacing,
                    ),
                    child: SizedBox(
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
                                mediaGroups,
                                row.indices[itemIndex],
                                thumbnailResizeWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGalleryGrid(
    List<MediaGroup> mediaGroups,
    int thumbnailResizeWidth,
  ) {
    final grid = _settings.gridAspectRatio.isAdaptive
        ? _buildAdaptiveGrid(mediaGroups, thumbnailResizeWidth)
        : GridView.builder(
            addAutomaticKeepAlives: false,
            scrollCacheExtent: const ScrollCacheExtent.pixels(200),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: _settings.gridAspectRatio.aspectRatio,
            ),
            itemCount: mediaGroups.length,
            itemBuilder: (context, index) {
              return _buildThumbnailTile(
                mediaGroups,
                index,
                thumbnailResizeWidth,
              );
            },
          );

    return Stack(
      fit: StackFit.expand,
      children: [
        grid,
        Positioned.fill(
          // This sits before the scrollable in the hit-test path, allowing
          // Ctrl+wheel to claim its signal before the grid scrolls.
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: _handleGridPointerSignal,
            onPointerPanZoomStart: _handleGridTrackpadPanZoomStart,
            onPointerPanZoomUpdate: _handleGridTrackpadPanZoomUpdate,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentFolderPath = _currentFolderPath();
    final canOpenCurrentFolder = currentFolderPath != null &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    final rawCount = _files.where((file) => file.isRaw).length;
    final imageCount = _files.length - rawCount;
    final adaptiveMediaGroups = buildAdaptiveMediaGroups(_files);
    final visibleMediaGroups = switch (_mediaFilter) {
      MediaFilter.adaptive => adaptiveMediaGroups,
      MediaFilter.all =>
        _files.map((file) => MediaGroup(primary: file)).toList(growable: false),
      MediaFilter.raw => _files
          .where((file) => file.isRaw)
          .map((file) => MediaGroup(primary: file))
          .toList(growable: false),
      MediaFilter.images => _files
          .where((file) => !file.isRaw)
          .map((file) => MediaGroup(primary: file))
          .toList(growable: false),
    };

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
              openFolderLabel: l10n.openFolder,
              openFilesLabel: l10n.openFiles,
              openCurrentFolderLabel: _currentFolderActionLabel(l10n),
              moreActionsTooltip: l10n.moreActionsTooltip,
              settingsTooltip: l10n.settingsTooltip,
              selectedMediaFilter: _mediaFilter,
              adaptiveCount: adaptiveMediaGroups.length,
              rawCount: rawCount,
              imageCount: imageCount,
              onMediaFilterSelected: (filter) {
                setState(() {
                  _mediaFilter = filter;
                });
              },
              onOpenSettings: _showSettings,
              onOpenFiles: _openFiles,
              onOpenFolder: _openFolder,
              onOpenCurrentFolder: !canOpenCurrentFolder
                  ? null
                  : () => _openCurrentFolder(currentFolderPath),
            ),
            Expanded(
              child: Stack(
                children: [
                  ExcludeSemantics(
                    child: _files.isEmpty
                        ? _EmptyGallery(
                            message: l10n.homeEmptyState,
                            openFolderLabel: l10n.openFolder,
                            openFilesLabel: l10n.openFiles,
                            onOpenFiles: _openFiles,
                            onOpenFolder: _openFolder,
                          )
                        : visibleMediaGroups.isEmpty
                            ? Center(child: Text(l10n.mediaFilterEmptyState))
                            : _buildGalleryGrid(
                                visibleMediaGroups,
                                thumbnailResizeWidth,
                              ),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _ThumbnailSizeControls(
                      largerThumbnailsTooltip: l10n.largerThumbnailsTooltip,
                      smallerThumbnailsTooltip: l10n.smallerThumbnailsTooltip,
                      onDecreaseThumbnailSize: _crossAxisCount > 1
                          ? () => _updateCrossAxisCount(-1)
                          : null,
                      onIncreaseThumbnailSize: _crossAxisCount < 10
                          ? () => _updateCrossAxisCount(1)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            _GalleryStatusBar(
              itemCountLabel: l10n.galleryItemCount(visibleMediaGroups.length),
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
  final String openFolderLabel;
  final String openFilesLabel;
  final String openCurrentFolderLabel;
  final String moreActionsTooltip;
  final String settingsTooltip;
  final MediaFilter selectedMediaFilter;
  final int adaptiveCount;
  final int rawCount;
  final int imageCount;
  final ValueChanged<MediaFilter> onMediaFilterSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;

  const _DesktopCommandBar({
    required this.title,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.moreActionsTooltip,
    required this.settingsTooltip,
    required this.selectedMediaFilter,
    required this.adaptiveCount,
    required this.rawCount,
    required this.imageCount,
    required this.onMediaFilterSelected,
    required this.onOpenSettings,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
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
              _GalleryActionsMenu(
                tooltip: moreActionsTooltip,
                openFolderLabel: openFolderLabel,
                openFilesLabel: openFilesLabel,
                openCurrentFolderLabel: openCurrentFolderLabel,
                onOpenFiles: onOpenFiles,
                onOpenFolder: onOpenFolder,
                onOpenCurrentFolder: onOpenCurrentFolder,
              ),
              const SizedBox(width: 4),
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
              MediaFilterButton(
                selectedFilter: selectedMediaFilter,
                adaptiveCount: adaptiveCount,
                rawCount: rawCount,
                imageCount: imageCount,
                onSelected: onMediaFilterSelected,
              ),
              const SizedBox(width: 8),
              if (!compact)
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(color: RawViewerColors.border),
                ),
              if (!compact) const SizedBox(width: 8),
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

enum _GalleryAction { openFiles, openFolder, openCurrentFolder }

class _GalleryActionsMenu extends StatelessWidget {
  final String tooltip;
  final String openFolderLabel;
  final String openFilesLabel;
  final String openCurrentFolderLabel;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;

  const _GalleryActionsMenu({
    required this.tooltip,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopPopupMenuButton<_GalleryAction>(
      tooltip: tooltip,
      offset: const Offset(0, 36),
      onSelected: (action) {
        switch (action) {
          case _GalleryAction.openFiles:
            onOpenFiles();
            break;
          case _GalleryAction.openFolder:
            onOpenFolder();
            break;
          case _GalleryAction.openCurrentFolder:
            onOpenCurrentFolder?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        desktopPopupMenuItem(
          value: _GalleryAction.openFiles,
          icon: Icons.file_open_outlined,
          label: openFilesLabel,
        ),
        desktopPopupMenuItem(
          value: _GalleryAction.openFolder,
          icon: Icons.folder_open_outlined,
          label: openFolderLabel,
        ),
        desktopPopupMenuItem(
          value: _GalleryAction.openCurrentFolder,
          enabled: onOpenCurrentFolder != null,
          icon: Icons.open_in_new,
          label: openCurrentFolderLabel,
        ),
      ],
      child: const DesktopPopupMenuTrigger(
        icon: Icons.more_vert,
      ),
    );
  }
}

class _ThumbnailSizeControls extends StatelessWidget {
  final String largerThumbnailsTooltip;
  final String smallerThumbnailsTooltip;
  final VoidCallback? onDecreaseThumbnailSize;
  final VoidCallback? onIncreaseThumbnailSize;

  const _ThumbnailSizeControls({
    required this.largerThumbnailsTooltip,
    required this.smallerThumbnailsTooltip,
    required this.onDecreaseThumbnailSize,
    required this.onIncreaseThumbnailSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopIconButton(
          icon: Icons.zoom_in,
          tooltip: largerThumbnailsTooltip,
          onPressed: onDecreaseThumbnailSize,
        ),
        const SizedBox(height: 4),
        DesktopIconButton(
          icon: Icons.zoom_out,
          tooltip: smallerThumbnailsTooltip,
          onPressed: onIncreaseThumbnailSize,
        ),
      ],
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
  final MediaFile mediaFile;
  final bool hasPairedJpeg;
  final ViewerSettings settings;
  final _TimestampRepository timestampRepository;
  final int resizeWidth;
  final ImageStore imageStore;
  final ValueChanged<double>? onAspectRatioChanged;
  final VoidCallback onTap;

  const _MediaThumbnailTile({
    super.key,
    required this.mediaFile,
    required this.hasPairedJpeg,
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
                        widget.hasPairedJpeg
                            ? AppLocalizations.of(context)!.rawJpegShortLabel
                            : AppLocalizations.of(context)!.rawShortLabel,
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
  final List<MediaGroup> mediaGroups;
  final int initialIndex;
  final int thumbnailResizeWidth;
  final ImageStore imageStore;
  final _TimestampRepository timestampRepository;
  final ViewerSettings settings;
  final VoidCallback onClose;

  const _ImagePreviewPage({
    required this.mediaGroups,
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
  bool _showPreviewFilmstrip = true;
  bool _showPreviewOverview = true;
  final Map<String, int> _rotationQuarterTurns = <String, int>{};
  final Map<String, _PreviewSource> _previewSources =
      <String, _PreviewSource>{};

  DateTime? _lastSwitchTime;
  Timer? _scrollStopTimer;
  Drag? _trackpadPageDrag;
  VelocityTracker? _trackpadVelocityTracker;
  Offset _lastTrackpadPan = Offset.zero;
  Duration? _lastTrackpadPanTimestamp;
  double _trackpadFlingVelocity = 0;
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
    _currentTimestampFuture = widget.timestampRepository.load(
      widget.mediaGroups[_currentIndex].primary.path,
    );
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _trackpadPageDrag?.cancel();
    _trackpadVelocityTracker = null;
    _isFastScrolling.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _currentTimestampFuture = widget.timestampRepository.load(
        widget.mediaGroups[_currentIndex].primary.path,
      );
      if ((_targetPage - index).abs() <= 1) {
        _targetPage = index;
      }
    });

    // We also preload here to cover cases where user swiped manually instead of mouse wheel
    _preloadThumbnails(index);
  }

  void _startTrackpadPageDrag(PointerPanZoomStartEvent event) {
    _trackpadPageDrag?.cancel();
    _trackpadVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, Offset.zero);
    _lastTrackpadPan = Offset.zero;
    _lastTrackpadPanTimestamp = event.timeStamp;
    _trackpadFlingVelocity = 0;
    if (!_pageController.hasClients) {
      return;
    }

    _trackpadPageDrag = _pageController.position.drag(
      DragStartDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        sourceTimeStamp: event.timeStamp,
        kind: event.kind,
      ),
      () => _trackpadPageDrag = null,
    );
  }

  void _updateTrackpadPageDrag(PointerPanZoomUpdateEvent event) {
    final panDelta = event.localPanDelta.dx * _trackpadPageDragSensitivity;
    final panPosition = event.localPan * _trackpadPageDragSensitivity;
    _trackpadVelocityTracker?.addPosition(event.timeStamp, panPosition);
    final previousTimestamp = _lastTrackpadPanTimestamp;
    if (previousTimestamp != null) {
      final elapsed = event.timeStamp - previousTimestamp;
      if (elapsed > Duration.zero && elapsed.inMilliseconds <= 100) {
        final instantaneousVelocity = (panPosition.dx - _lastTrackpadPan.dx) /
            elapsed.inMicroseconds *
            Duration.microsecondsPerSecond;
        if (instantaneousVelocity.isFinite) {
          _trackpadFlingVelocity = _trackpadFlingVelocity == 0
              ? instantaneousVelocity
              : _trackpadFlingVelocity * 0.35 + instantaneousVelocity * 0.65;
        }
      }
    }
    _lastTrackpadPan = panPosition;
    _lastTrackpadPanTimestamp = event.timeStamp;
    if (panDelta == 0) {
      return;
    }

    _trackpadPageDrag?.update(
      DragUpdateDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        sourceTimeStamp: event.timeStamp,
        delta: Offset(panDelta, 0),
        primaryDelta: panDelta,
        kind: event.kind,
      ),
    );
  }

  void _endTrackpadPageDrag(PointerPanZoomEndEvent event) {
    final drag = _trackpadPageDrag;
    _trackpadPageDrag = null;
    final trackedVelocity =
        _trackpadVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    _trackpadVelocityTracker = null;
    final velocity = trackedVelocity.abs() >= _trackpadFlingMinVelocity
        ? trackedVelocity
        : _trackpadFlingVelocity.abs() >= _trackpadFlingMinVelocity
            ? _trackpadFlingVelocity
            : 0.0;
    drag?.end(
      DragEndDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        velocity: Velocity(pixelsPerSecond: Offset(velocity, 0)),
        primaryVelocity: velocity,
      ),
    );
  }

  void _cancelTrackpadPageDrag() {
    _trackpadPageDrag?.cancel();
    _trackpadPageDrag = null;
    _trackpadVelocityTracker = null;
  }

  void _preloadThumbnails(int centerIndex, {bool isFastScrolling = false}) {
    final range = isFastScrolling ? 1 : 3;
    for (int i = 1; i <= range; i++) {
      _preloadIndex(centerIndex + i);
      _preloadIndex(centerIndex - i);
    }
  }

  void _preloadIndex(int index) {
    if (index < 0 || index >= widget.mediaGroups.length) return;

    final mediaFile = widget.mediaGroups[index].primary;
    final String filePath = mediaFile.path;

    if (mediaFile.isRaw) {
      // Warm a bounded thumbnail layer instead of several full-resolution RAW
      // images. The active page paints this cached layer immediately, then
      // upgrades itself in the background when needed.
      unawaited(widget.imageStore
          .load(
            filePath,
            RawLayer.fastPreview,
            targetWidth: _previewFilmstripDecodeWidth,
            priority: TaskPriority.low,
          )
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

  int get _previewFilmstripDecodeWidth => bucketDecodeWidth(
        kPreviewFilmstripItemWidth * MediaQuery.devicePixelRatioOf(context),
      );

  void _switchPage(int delta) {
    int newTarget = _targetPage + delta;
    if (newTarget < 0) newTarget = 0;
    if (newTarget >= widget.mediaGroups.length) {
      newTarget = widget.mediaGroups.length - 1;
    }

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
            now.difference(_lastSwitchTime!) <
                kImagePreviewRapidSwitchThreshold);
    _lastSwitchTime = now;

    _targetPage = newTarget;
    // Preload thumbnails IMMEDIATELY on scroll intention, rather than waiting for animation to hit 50%
    _preloadThumbnails(_targetPage,
        isFastScrolling: fastScroll || _isFastScrolling.value);

    // Touch and trackpad swipes move the PageView directly and never take this
    // branch. Disabling the setting therefore only removes animation from
    // discrete mouse-wheel navigation.
    if (!widget.settings.pageSwitchAnimationEnabled) {
      _scrollStopTimer?.cancel();
      _isFastScrolling.value = false;
      _pageController.jumpToPage(_targetPage);
      return;
    }

    void startFastScrollTimer() {
      _isFastScrolling.value = true;
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(kImagePreviewRapidSwitchSettleDelay, () {
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
        duration: kImagePreviewPageSwitchDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _jumpToPage(int index) {
    if (index < 0 || index >= widget.mediaGroups.length) {
      return;
    }
    if (index == _currentIndex && index == _targetPage) {
      return;
    }

    _targetPage = index;
    _preloadThumbnails(index);
    _scrollStopTimer?.cancel();
    _isFastScrolling.value = false;

    if (!widget.settings.pageSwitchAnimationEnabled) {
      _pageController.jumpToPage(index);
      return;
    }

    _pageController.animateToPage(
      index,
      duration: kImagePreviewPageSwitchDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _rotateImage(String filePath, int quarterTurns) {
    setState(() {
      _rotationQuarterTurns[filePath] = rotateImageQuarterTurns(
        _rotationQuarterTurns[filePath] ?? 0,
        quarterTurns,
      );
    });
  }

  void _resetImageRotation(String filePath) {
    setState(() {
      _rotationQuarterTurns.remove(filePath);
    });
  }

  _PreviewSource _previewSourceFor(MediaGroup mediaGroup) {
    return _previewSources[mediaGroup.primary.path] ??
        (widget.settings.preferFastPreviewForRaw
            ? _PreviewSource.fastPreview
            : _PreviewSource.decodedRaw);
  }

  void _selectPreviewSource(MediaGroup mediaGroup, _PreviewSource source) {
    if (!mediaGroup.isRaw ||
        (source == _PreviewSource.jpeg && !mediaGroup.hasPairedJpeg)) {
      return;
    }
    setState(() {
      _previewSources[mediaGroup.primary.path] = source;
    });
  }

  IconData _previewSourceIcon(_PreviewSource source) {
    switch (source) {
      case _PreviewSource.fastPreview:
        return Icons.bolt_outlined;
      case _PreviewSource.decodedRaw:
        return Icons.camera_alt_outlined;
      case _PreviewSource.jpeg:
        return Icons.image_outlined;
    }
  }

  String _previewSourceLabel(
    AppLocalizations l10n,
    _PreviewSource source,
  ) {
    switch (source) {
      case _PreviewSource.fastPreview:
        return l10n.fastPreviewShortLabel;
      case _PreviewSource.decodedRaw:
        return l10n.rawShortLabel;
      case _PreviewSource.jpeg:
        return 'JPG';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentMediaGroup = widget.mediaGroups[_currentIndex];
    final currentFilePath = widget.mediaGroups[_currentIndex].primary.path;
    final currentPreviewSource = _previewSourceFor(currentMediaGroup);
    final previewTop =
        MediaQuery.paddingOf(context).top + kImagePreviewToolbarHeight;
    final pageDragDevices =
        Set<PointerDeviceKind>.from(ScrollConfiguration.of(context).dragDevices)
          ..remove(PointerDeviceKind.trackpad);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            top: previewTop,
            bottom: _showPreviewFilmstrip
                ? kPreviewFilmstripHeight + MediaQuery.paddingOf(context).bottom
                : 0,
            child: PageView.builder(
              controller: _pageController,
              // Trackpad pages are moved from raw pan deltas so their position
              // remains directly coupled to the user's fingers.
              scrollBehavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: pageDragDevices,
              ),
              physics: _isLocked
                  ? const NeverScrollableScrollPhysics()
                  : const FastPageScrollPhysics(),
              dragStartBehavior: DragStartBehavior.down,
              allowImplicitScrolling: true,
              padEnds: true,
              itemCount: widget.mediaGroups.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final mediaGroup = widget.mediaGroups[index];
                final filePath = mediaGroup.primary.path;
                return _SingleImagePreview(
                  key: ValueKey(filePath),
                  mediaGroup: mediaGroup,
                  thumbnailResizeWidth: widget.thumbnailResizeWidth,
                  previewThumbnailResizeWidth: _previewFilmstripDecodeWidth,
                  imageStore: widget.imageStore,
                  settings: widget.settings,
                  rotationQuarterTurns: _rotationQuarterTurns[filePath] ?? 0,
                  previewSource: _previewSourceFor(mediaGroup),
                  onRotationRequested: (quarterTurns) =>
                      _rotateImage(filePath, quarterTurns),
                  onResetRotationRequested: () => _resetImageRotation(filePath),
                  onSwitchRequest: _switchPage,
                  onTrackpadPanStart: _startTrackpadPageDrag,
                  onTrackpadPanUpdate: _updateTrackpadPageDrag,
                  onTrackpadPanEnd: _endTrackpadPageDrag,
                  onTrackpadPanCancel: _cancelTrackpadPageDrag,
                  isActive: index == _currentIndex,
                  showPreviewOverview: _showPreviewOverview,
                  overviewBottomInset: 0,
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
          ),
          if (_showPreviewFilmstrip)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _PreviewFilmstrip(
                mediaGroups: widget.mediaGroups,
                currentIndex: _currentIndex,
                imageStore: widget.imageStore,
                decodeWidth: _previewFilmstripDecodeWidth,
                onIndexSelected: _jumpToPage,
              ),
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
                return Container(
                  decoration: BoxDecoration(
                    color: RawViewerColors.surface.withValues(alpha: 0.94),
                    border: const Border(
                      bottom: BorderSide(color: RawViewerColors.border),
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: SizedBox(
                      height: kImagePreviewToolbarHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          children: [
                            DesktopIconButton(
                              icon: Icons.arrow_back,
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              onPressed: widget.onClose,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    path.basename(currentFilePath),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: RawViewerColors.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    timestampText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: RawViewerColors.mutedText,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                            DesktopPopupMenuButton<_PreviewDisplayControl>(
                              tooltip: l10n.previewDisplayControlsTooltip,
                              onSelected: (control) {
                                setState(() {
                                  switch (control) {
                                    case _PreviewDisplayControl.filmstrip:
                                      _showPreviewFilmstrip =
                                          !_showPreviewFilmstrip;
                                      break;
                                    case _PreviewDisplayControl.overview:
                                      _showPreviewOverview =
                                          !_showPreviewOverview;
                                      break;
                                  }
                                });
                              },
                              itemBuilder: (context) => [
                                desktopPopupMenuItem(
                                  value: _PreviewDisplayControl.filmstrip,
                                  icon: Icons.view_carousel_outlined,
                                  selected: _showPreviewFilmstrip,
                                  label: l10n.previewFilmstripTitle,
                                ),
                                desktopPopupMenuItem(
                                  value: _PreviewDisplayControl.overview,
                                  icon: Icons.map_outlined,
                                  selected: _showPreviewOverview,
                                  label: l10n.previewOverviewTitle,
                                ),
                              ],
                              child: DesktopPopupMenuTrigger(
                                icon: Icons.tune,
                                selected: _showPreviewFilmstrip ||
                                    _showPreviewOverview,
                              ),
                            ),
                            if (currentMediaGroup.isRaw) ...[
                              const SizedBox(width: 8),
                              DesktopPopupMenuButton<_PreviewSource>(
                                tooltip: l10n.rawPreviewSourceSectionTitle,
                                initialValue: currentPreviewSource,
                                onSelected: (source) => _selectPreviewSource(
                                  currentMediaGroup,
                                  source,
                                ),
                                child: DesktopPopupMenuLabelTrigger(
                                  icon: _previewSourceIcon(
                                    currentPreviewSource,
                                  ),
                                  label: _previewSourceLabel(
                                    l10n,
                                    currentPreviewSource,
                                  ),
                                ),
                                itemBuilder: (context) => [
                                  desktopPopupMenuItem(
                                    value: _PreviewSource.fastPreview,
                                    icon: Icons.bolt_outlined,
                                    selected: currentPreviewSource ==
                                        _PreviewSource.fastPreview,
                                    label: l10n.fastPreviewShortLabel,
                                  ),
                                  desktopPopupMenuItem(
                                    value: _PreviewSource.decodedRaw,
                                    icon: Icons.camera_alt_outlined,
                                    selected: currentPreviewSource ==
                                        _PreviewSource.decodedRaw,
                                    label: l10n.rawShortLabel,
                                  ),
                                  if (currentMediaGroup.hasPairedJpeg)
                                    desktopPopupMenuItem(
                                      value: _PreviewSource.jpeg,
                                      icon: Icons.image_outlined,
                                      selected: currentPreviewSource ==
                                          _PreviewSource.jpeg,
                                      label: 'JPG',
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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

class _PreviewFilmstrip extends StatefulWidget {
  final List<MediaGroup> mediaGroups;
  final int currentIndex;
  final ImageStore imageStore;
  final int decodeWidth;
  final ValueChanged<int> onIndexSelected;

  const _PreviewFilmstrip({
    required this.mediaGroups,
    required this.currentIndex,
    required this.imageStore,
    required this.decodeWidth,
    required this.onIndexSelected,
  });

  @override
  State<_PreviewFilmstrip> createState() => _PreviewFilmstripState();
}

class _PreviewFilmstripState extends State<_PreviewFilmstrip> {
  late final ScrollController _scrollController;
  double? _lastViewportWidth;
  bool _centerRequestScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scheduleCenterCurrent(animated: false);
  }

  @override
  void didUpdateWidget(_PreviewFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _scheduleCenterCurrent(animated: true);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCenterCurrent({required bool animated}) {
    if (_centerRequestScheduled) {
      return;
    }
    _centerRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerRequestScheduled = false;
      if (!mounted) {
        return;
      }
      _centerCurrent(animated: animated);
    });
  }

  void _centerCurrent({required bool animated}) {
    if (!_scrollController.hasClients || widget.mediaGroups.isEmpty) {
      _scheduleCenterCurrent(animated: animated);
      return;
    }

    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final targetOffset = (widget.currentIndex * kPreviewFilmstripItemExtent)
        .clamp(0.0, maxScrollExtent)
        .toDouble();
    if ((targetOffset - _scrollController.offset).abs() < 0.5) {
      return;
    }

    if (animated) {
      unawaited(_scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      ));
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastViewportWidth != constraints.maxWidth) {
          _lastViewportWidth = constraints.maxWidth;
          _scheduleCenterCurrent(animated: false);
        }
        final viewportWidth = math.max(0.0, constraints.maxWidth - 24);
        final sidePadding = math.max(
          0.0,
          (viewportWidth - kPreviewFilmstripItemWidth) / 2,
        );
        return Container(
          height: kPreviewFilmstripHeight + bottomPadding,
          padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding + 10),
          decoration: BoxDecoration(
            color: RawViewerColors.surface.withValues(alpha: 0.96),
            border: const Border(
              top: BorderSide(color: RawViewerColors.border),
            ),
          ),
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: sidePadding),
            scrollCacheExtent: ScrollCacheExtent.pixels(
              kPreviewFilmstripItemExtent * 4,
            ),
            itemExtent: kPreviewFilmstripItemExtent,
            itemCount: widget.mediaGroups.length,
            itemBuilder: (context, index) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: kPreviewFilmstripItemWidth,
                    height: 58,
                    child: _PreviewFilmstripThumbnail(
                      key: ValueKey(widget.mediaGroups[index].primary.path),
                      mediaGroup: widget.mediaGroups[index],
                      imageStore: widget.imageStore,
                      decodeWidth: widget.decodeWidth,
                      selected: index == widget.currentIndex,
                      onTap: () => widget.onIndexSelected(index),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _PreviewFilmstripThumbnail extends StatefulWidget {
  final MediaGroup mediaGroup;
  final ImageStore imageStore;
  final int decodeWidth;
  final bool selected;
  final VoidCallback onTap;

  const _PreviewFilmstripThumbnail({
    super.key,
    required this.mediaGroup,
    required this.imageStore,
    required this.decodeWidth,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_PreviewFilmstripThumbnail> createState() =>
      _PreviewFilmstripThumbnailState();
}

class _PreviewFilmstripThumbnailState
    extends State<_PreviewFilmstripThumbnail> {
  ViewerImage? _rawImage;
  bool _failed = false;
  int _generation = 0;

  String get _filePath => widget.mediaGroup.primary.path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PreviewFilmstripThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_filePath != oldWidget.mediaGroup.primary.path ||
        widget.decodeWidth != oldWidget.decodeWidth) {
      _generation++;
      _rawImage?.dispose();
      _rawImage = null;
      _failed = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _rawImage?.dispose();
    super.dispose();
  }

  void _load() {
    if (!widget.mediaGroup.isRaw) {
      return;
    }

    final generation = _generation;
    unawaited(widget.imageStore
        .load(
      _filePath,
      RawLayer.fastPreview,
      targetWidth: widget.decodeWidth,
      priority: TaskPriority.low,
    )
        .then((image) {
      if (!mounted || generation != _generation) {
        image?.dispose();
        return;
      }
      setState(() {
        _rawImage = image;
        _failed = image == null;
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (widget.mediaGroup.isRaw) {
      image = _rawImage == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: RawViewerColors.raisedSurface),
                Center(
                  child: _failed
                      ? const Icon(Icons.broken_image_outlined,
                          color: RawViewerColors.mutedText, size: 18)
                      : const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              ],
            )
          : RawImage(
              image: _rawImage!.image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            );
    } else {
      image = Image(
        image: ResizeImage(
          FileImage(File(_filePath)),
          width: widget.decodeWidth,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          color: RawViewerColors.raisedSurface,
          child: const Icon(Icons.broken_image_outlined,
              color: RawViewerColors.mutedText, size: 18),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(5),
        splashColor: RawViewerColors.accentMuted,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: image,
            ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.selected
                        ? RawViewerColors.accent
                        : RawViewerColors.border,
                    width: widget.selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewOverviewMap extends StatelessWidget {
  final Widget image;
  final TransformationController transformationController;
  final Size viewportSize;

  const _PreviewOverviewMap({
    required this.image,
    required this.transformationController,
    required this.viewportSize,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: kPreviewOverviewMapWidth,
        height: kPreviewOverviewMapHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RawViewerColors.surface,
            border: Border.all(color: RawViewerColors.border),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 1),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mapSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    AnimatedBuilder(
                      animation: transformationController,
                      builder: (context, child) {
                        final viewportRect = previewOverviewViewportRect(
                          transform: transformationController.value,
                          viewportSize: viewportSize,
                          mapSize: mapSize,
                        );
                        return CustomPaint(
                          painter: _PreviewOverviewViewportPainter(
                            viewportRect: viewportRect,
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewOverviewViewportPainter extends CustomPainter {
  final Rect viewportRect;

  const _PreviewOverviewViewportPainter({required this.viewportRect});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = RawViewerColors.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = RawViewerColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(viewportRect, fillPaint);
    canvas.drawRect(viewportRect, strokePaint);
  }

  @override
  bool shouldRepaint(_PreviewOverviewViewportPainter oldDelegate) {
    return oldDelegate.viewportRect != viewportRect;
  }
}

enum _PreviewDisplayControl { filmstrip, overview }

enum _PreviewSource { fastPreview, decodedRaw, jpeg }

/// Rotates an image view in clockwise 90-degree increments.
int rotateImageQuarterTurns(int currentQuarterTurns, int delta) {
  return (currentQuarterTurns + delta) % 4;
}

class _SingleImagePreview extends StatefulWidget {
  final MediaGroup mediaGroup;
  final int thumbnailResizeWidth;
  final int previewThumbnailResizeWidth;
  final ImageStore imageStore;
  final ViewerSettings settings;
  final int rotationQuarterTurns;
  final _PreviewSource previewSource;
  final ValueChanged<int> onRotationRequested;
  final VoidCallback onResetRotationRequested;
  final ValueChanged<int> onSwitchRequest;
  final ValueChanged<PointerPanZoomStartEvent> onTrackpadPanStart;
  final ValueChanged<PointerPanZoomUpdateEvent> onTrackpadPanUpdate;
  final ValueChanged<PointerPanZoomEndEvent> onTrackpadPanEnd;
  final VoidCallback onTrackpadPanCancel;
  final bool isActive;
  final bool showPreviewOverview;
  final double overviewBottomInset;
  final ValueNotifier<bool> isFastScrolling;
  final ValueChanged<bool>? onScaleStateChanged;

  const _SingleImagePreview({
    super.key,
    required this.mediaGroup,
    required this.thumbnailResizeWidth,
    required this.previewThumbnailResizeWidth,
    required this.imageStore,
    required this.settings,
    required this.rotationQuarterTurns,
    required this.previewSource,
    required this.onRotationRequested,
    required this.onResetRotationRequested,
    required this.onSwitchRequest,
    required this.onTrackpadPanStart,
    required this.onTrackpadPanUpdate,
    required this.onTrackpadPanEnd,
    required this.onTrackpadPanCancel,
    required this.isActive,
    required this.showPreviewOverview,
    required this.overviewBottomInset,
    required this.isFastScrolling,
    this.onScaleStateChanged,
  });

  String get filePath => mediaGroup.primary.path;
  bool get isRaw => mediaGroup.isRaw;
  bool get hasPairedJpeg => mediaGroup.hasPairedJpeg;

  @override
  State<_SingleImagePreview> createState() => _SingleImagePreviewState();
}

class _SingleImagePreviewState extends State<_SingleImagePreview> {
  ViewerImage? _fastPreviewImage;
  ViewerImage? _decodedRawPreviewImage;
  bool _hasFullResolutionFastPreview = false;
  bool _fullResolutionFastPreviewRequested = false;
  bool _isLoadingDecodedRawPreview = false;
  late int _rawDecodeHalfSize;
  final TransformationController _transformationController =
      TransformationController();
  bool _panEnabled = false;
  bool _isZoomed = false;
  // Mouse-wheel zoom is explicit so it does not conflict with navigation.
  // Touch keeps InteractiveViewer's pinch flow, while trackpad pinch is
  // handled from raw pan/zoom updates.
  bool _scaleEnabled = false;
  final Set<int> _activePointers = {};
  double _lastTrackpadScale = 1;
  bool _isTrackpadScaling = false;
  bool _isTrackpadPageDrag = false;
  Timer? _fitScaleLockTimer;
  bool _isFitScaleLocked = false;
  _PreviewScaleDirection? _fitScaleLockDirection;

  /// Only the expensive decoded-RAW task is tracked for cancellation.
  ///
  /// The fast preview is deliberately never cancelled: it is cheap, and the
  /// worker dedupes it by path, so cancelling ours would also resolve a grid
  /// tile's shared request to null and leave that tile showing a broken image.
  WorkerTask<LibRawImage?>? _decodedRawTask;

  bool get _isShowingPairedJpeg => widget.previewSource == _PreviewSource.jpeg;
  bool get _preferFastPreviewForRaw =>
      widget.previewSource == _PreviewSource.fastPreview;

  @override
  void initState() {
    super.initState();
    _rawDecodeHalfSize = widget.settings.useHalfSizeRawDecode ? 1 : 0;

    // Take a cached fast preview synchronously so the first frame of a page
    // switch already paints an image instead of an empty (black) area. Prefer
    // the full-resolution entry, but fall back to the grid's thumbnail-sized
    // one: showing it slightly soft for a moment beats showing black.
    if (widget.isRaw) {
      _fastPreviewImage = widget.imageStore.peek(
        widget.filePath,
        RawLayer.fastPreview,
      );
      if (_fastPreviewImage != null) {
        _hasFullResolutionFastPreview = true;
      } else {
        _fastPreviewImage = widget.imageStore.peek(
              widget.filePath,
              RawLayer.fastPreview,
              targetWidth: widget.thumbnailResizeWidth,
            ) ??
            widget.imageStore.peek(
              widget.filePath,
              RawLayer.fastPreview,
              targetWidth: widget.previewThumbnailResizeWidth,
            );
      }
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
      _clearFitScaleLock();
      _transformationController.value = Matrix4.identity();
      _cancelDecodedRawTask();
    }

    if (widget.rotationQuarterTurns != oldWidget.rotationQuarterTurns) {
      _clearFitScaleLock();
      _transformationController.value = Matrix4.identity();
    }

    if (widget.previewSource != oldWidget.previewSource) {
      if (widget.previewSource != _PreviewSource.decodedRaw) {
        _decodedRawTask?.cancel();
        _decodedRawTask = null;
        _isLoadingDecodedRawPreview = false;
      } else if (widget.isActive &&
          !widget.isFastScrolling.value &&
          _decodedRawPreviewImage == null) {
        unawaited(_loadRawDisplayLayers());
      }
    }

    if (widget.isActive && !oldWidget.isActive) {
      // Reload skips whatever layer is already available.
      unawaited(_loadRawDisplayLayers());
    }
  }

  @override
  void dispose() {
    widget.isFastScrolling.removeListener(_onFastScrollingChanged);
    _clearFitScaleLock();
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
    final newPanEnabled =
        (scale - _previewFitScale).abs() > _previewScaleEpsilon;
    if (_panEnabled != newPanEnabled || _isZoomed != newPanEnabled) {
      setState(() {
        _panEnabled = newPanEnabled;
        _isZoomed = newPanEnabled;
      });
    }
  }

  void _lockAtFitScale(_PreviewScaleDirection direction) {
    _isFitScaleLocked = true;
    _fitScaleLockDirection = direction;
    _fitScaleLockTimer?.cancel();
    _fitScaleLockTimer = Timer(_previewFitScaleLockDuration, () {
      _fitScaleLockTimer = null;
      _isFitScaleLocked = false;
      _fitScaleLockDirection = null;
    });
  }

  void _clearFitScaleLock() {
    _fitScaleLockTimer?.cancel();
    _fitScaleLockTimer = null;
    _isFitScaleLocked = false;
    _fitScaleLockDirection = null;
  }

  Future<void> _loadRawDisplayLayers() async {
    // For non-RAW files, we rely entirely on Flutter's Image.file
    if (!widget.isRaw || !widget.isActive) return;

    if (!_hasFullResolutionFastPreview &&
        !_fullResolutionFastPreviewRequested) {
      _fullResolutionFastPreviewRequested = true;
      final fastPreviewPriority =
          widget.isFastScrolling.value ? TaskPriority.low : TaskPriority.high;

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
          _hasFullResolutionFastPreview = true;
        });
      }
    }

    if (!widget.isActive || widget.isFastScrolling.value) {
      return;
    }

    if (_preferFastPreviewForRaw || _isShowingPairedJpeg) return;
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
    if (!mounted ||
        !widget.isActive ||
        _preferFastPreviewForRaw ||
        _isShowingPairedJpeg) {
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

  void _applyScale(
    double scaleChange,
    Offset focalPoint, {
    bool lockAtFitScale = false,
  }) {
    if (scaleChange <= 0 || !scaleChange.isFinite) {
      return;
    }
    if ((scaleChange - 1).abs() < 0.0001) {
      return;
    }

    final direction = scaleChange > 1
        ? _PreviewScaleDirection.zoomIn
        : _PreviewScaleDirection.zoomOut;

    if (_isFitScaleLocked) {
      if (lockAtFitScale && direction == _fitScaleLockDirection) {
        _lockAtFitScale(direction);
        return;
      }
      _clearFitScaleLock();
    }

    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = clampPreviewScale(currentScale * scaleChange);
    if (shouldResetPreviewPositionAtFitScale(
      currentScale: currentScale,
      targetScale: targetScale,
    )) {
      // Crossing the fitted size in either direction is a distinct step.
      // Pointer zoom stays here until its current scroll/pinch sequence ends.
      _transformationController.value = Matrix4.identity();
      if (lockAtFitScale) {
        _lockAtFitScale(direction);
      }
      return;
    }
    final effectiveScaleChange = targetScale / currentScale;
    if ((effectiveScaleChange - 1).abs() < 0.0001) {
      return;
    }

    final scaleMatrix = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(
        effectiveScaleChange,
        effectiveScaleChange,
        effectiveScaleChange,
        1,
      )
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _transformationController.value = scaleMatrix * matrix;
  }

  void _zoomBy(double scaleChange) {
    final size = context.size;
    if (size == null) {
      return;
    }
    _applyScale(scaleChange, size.center(Offset.zero));
  }

  void _resetView() {
    _clearFitScaleLock();
    _transformationController.value = Matrix4.identity();
    widget.onResetRotationRequested();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final scaleEvent = event as PointerScaleEvent;
        _applyScale(
          scaleEvent.scale,
          scaleEvent.localPosition,
          lockAtFitScale: true,
        );
      });
      return;
    }

    if (event is! PointerScrollEvent) {
      return;
    }

    final scrollDelta = event.scrollDelta;
    final primaryDelta = scrollDelta.dx.abs() > scrollDelta.dy.abs()
        ? scrollDelta.dx
        : scrollDelta.dy;
    if (primaryDelta == 0) {
      return;
    }

    final shouldZoom = _isZoomModifierPressed();
    if (event.kind == PointerDeviceKind.trackpad && !shouldZoom) {
      // Let PageView consume trackpad scroll signals directly. On platforms
      // that emit these instead of pan/zoom events, this preserves follow.
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      scrollEvent.respond(allowPlatformDefault: false);
      if (shouldZoom) {
        _applyScale(
          primaryDelta < 0 ? 1.1 : 0.9,
          scrollEvent.localPosition,
          lockAtFitScale: true,
        );
      } else {
        widget.onSwitchRequest(primaryDelta > 0 ? 1 : -1);
      }
    });
  }

  void _handleTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _lastTrackpadScale = 1;
    _isTrackpadScaling = false;
    // Once zoomed, InteractiveViewer owns two-finger panning of the image.
    // At the fit scale, drive PageView with the same drag activity used by
    // touch so page position stays directly under the gesture.
    _isTrackpadPageDrag = !_panEnabled;
    if (_isTrackpadPageDrag) {
      widget.onTrackpadPanStart(event);
    }
  }

  void _handleTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale > 0 && event.scale.isFinite) {
      final scaleChange = event.scale / _lastTrackpadScale;
      _lastTrackpadScale = event.scale;
      if (_isTrackpadScaling ||
          (event.scale - 1).abs() >= _previewTrackpadScaleSlop) {
        if (!_isTrackpadScaling && _isTrackpadPageDrag) {
          widget.onTrackpadPanCancel();
          _isTrackpadPageDrag = false;
        }
        _isTrackpadScaling = true;
        _applyScale(
          scaleChange,
          event.localPosition,
          lockAtFitScale: true,
        );
        return;
      }
    }

    if (_isTrackpadPageDrag) {
      widget.onTrackpadPanUpdate(event);
    }
  }

  void _handleTrackpadPanZoomEnd(PointerPanZoomEndEvent event) {
    if (_isTrackpadPageDrag && !_isTrackpadScaling) {
      widget.onTrackpadPanEnd(event);
    }
    _clearFitScaleLock();
    _isTrackpadPageDrag = false;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        return Stack(
          children: [
            Listener(
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: _handleTrackpadPanZoomStart,
              onPointerPanZoomUpdate: _handleTrackpadPanZoomUpdate,
              onPointerPanZoomEnd: _handleTrackpadPanZoomEnd,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              onPointerHover: _onPointerHover,
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: kMinPreviewScale,
                  maxScale: kMaxPreviewScale,
                  panEnabled: _panEnabled,
                  scaleEnabled: _scaleEnabled,
                  child: RotatedBox(
                    quarterTurns: widget.rotationQuarterTurns,
                    child: _isShowingPairedJpeg
                        ? _buildBitmapPreview(
                            widget.mediaGroup.pairedJpeg!.path)
                        : widget.isRaw
                            ? _buildRawPreview()
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildBitmapPreview(widget.filePath)
                                ],
                              ),
                  ),
                ),
              ),
            ),
            if (widget.isActive && widget.showPreviewOverview && _isZoomed)
              Positioned(
                right: 12,
                bottom: widget.overviewBottomInset +
                    MediaQuery.paddingOf(context).bottom +
                    _previewImageControlsHeight +
                    _previewOverviewGap +
                    12,
                child: _PreviewOverviewMap(
                  image: RotatedBox(
                    quarterTurns: widget.rotationQuarterTurns,
                    child: _buildOverviewImage(),
                  ),
                  transformationController: _transformationController,
                  viewportSize: viewportSize,
                ),
              ),
            Positioned(
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: RawViewerColors.surface.withValues(alpha: 0.94),
                  border: Border.all(color: RawViewerColors.border),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DesktopIconButton(
                        icon: Icons.rotate_left,
                        tooltip: l10n.rotateImageCounterclockwiseTooltip,
                        onPressed: () => widget.onRotationRequested(-1),
                      ),
                      const SizedBox(width: 2),
                      DesktopIconButton(
                        icon: Icons.rotate_right,
                        tooltip: l10n.rotateImageTooltip,
                        onPressed: () => widget.onRotationRequested(1),
                      ),
                      const SizedBox(width: 5),
                      DesktopIconButton(
                        icon: Icons.zoom_in,
                        tooltip: l10n.zoomInImageTooltip,
                        onPressed: () => _zoomBy(_previewControlZoomStep),
                      ),
                      const SizedBox(width: 2),
                      DesktopIconButton(
                        icon: Icons.zoom_out,
                        tooltip: l10n.zoomOutImageTooltip,
                        onPressed: () => _zoomBy(1 / _previewControlZoomStep),
                      ),
                      const SizedBox(width: 2),
                      DesktopIconButton(
                        icon: Icons.filter_center_focus,
                        tooltip: l10n.resetImageViewTooltip,
                        onPressed: _resetView,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverviewImage() {
    if (_isShowingPairedJpeg) {
      return _buildOverviewBitmap(widget.mediaGroup.pairedJpeg!.path);
    }
    if (widget.isRaw) {
      final image = _preferFastPreviewForRaw
          ? _fastPreviewImage
          : _decodedRawPreviewImage ?? _fastPreviewImage;
      if (image != null) {
        return RawImage(
          image: image.image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
        );
      }
      return const SizedBox.shrink();
    }
    return _buildOverviewBitmap(widget.filePath);
  }

  Widget _buildOverviewBitmap(String filePath) {
    return Image(
      image: ResizeImage(
        FileImage(File(filePath)),
        width:
            (kPreviewOverviewMapWidth * MediaQuery.devicePixelRatioOf(context))
                .round(),
      ),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
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
            top: 24,
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

  Widget _buildBitmapPreview(String filePath) {
    final file = File(filePath);

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
        mass: 0.7,
        stiffness: 1600.0,
        ratio: 1.0,
      );
}
