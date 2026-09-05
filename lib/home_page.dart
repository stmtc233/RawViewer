import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

import 'core/decode_target.dart';
import 'core/media_timestamps.dart';
import 'core/media_types.dart';
import 'core/preferences_repository.dart';
import 'core/raw_view_mode.dart';
import 'gallery/grid_zoom_accumulator.dart';
import 'gallery/media_library.dart';
import 'core/platform_channels.dart';
import 'core/pointer_modifiers.dart';
import 'gallery/widgets/desktop_command_bar.dart';
import 'gallery/widgets/gallery_chrome.dart';
import 'gallery/widgets/media_thumbnail_tile.dart';
import 'image_store.dart';
import 'justified_grid_layout.dart';
import 'l10n/app_localizations.dart';
import 'lru_cache.dart';
import 'media_filter.dart';
import 'media_group.dart';
import 'preview/image_preview_page.dart';
import 'preview/preview_geometry.dart';
import 'settings_page.dart';
import 'viewer_image.dart';
import 'worker_service.dart';

enum _OpenedSourceKind { none, folder, files }

class _LoadedDirectory {
  const _LoadedDirectory({
    required this.path,
    required this.files,
  });

  final String path;
  final List<MediaFile> files;
}

class HomePage extends StatefulWidget {
  final ValueChanged<AppLanguage> onAppLanguageChanged;
  final Future<void>? desktopWindowReady;

  const HomePage({
    super.key,
    required this.onAppLanguageChanged,
    this.desktopWindowReady,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _currentDirectoryPath;
  String? _deferredDirectoryPath;
  int? _openedDirectoryCount;
  String? _lastSyncedWindowsContextMenuText;
  List<MediaFile> _files = [];
  _OpenedSourceKind _openedSourceKind = _OpenedSourceKind.none;
  // Use LRU Cache to limit memory usage.
  late LruCache<String, ViewerImage> _imageCache;
  late ImageStore _imageStore;
  final TimestampRepository _timestampRepository = TimestampRepository();
  ViewerSettings _settings = const ViewerSettings();
  MediaFilter _mediaFilter = defaultMediaFilter;
  int _crossAxisCount = 4;
  bool _hasUserConfiguredGridAspectRatio = false;
  final GridZoomAccumulator _gridZoom = GridZoomAccumulator();
  Timer? _gridZoomResetTimer;
  final Map<String, double> _mediaAspectRatios = <String, double>{};
  final Map<String, double> _pendingMediaAspectRatios = <String, double>{};
  bool _mediaAspectRatioUpdateScheduled = false;
  int _lastGalleryPrefetchAnchor = -1;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _initCache();
    unawaited(_listenForDesktopOpenRequests());
    unawaited(_refreshWindowsContextMenuAfterFirstFrame());
  }

  @override
  void dispose() {
    _gridZoomResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final prefs = const PreferencesRepository();
    final stored = await prefs.loadViewPreferences();
    if (!mounted) return;
    setState(() {
      _crossAxisCount = stored.crossAxisCount;
      if (!_hasUserConfiguredGridAspectRatio) {
        _settings = _settings.copyWith(
          gridAspectRatio: stored.gridAspectRatio ?? GridAspectRatio.ratio3x2,
        );
      }
      _settings = _settings.copyWith(
        pageSwitchAnimationEnabled: stored.pageSwitchAnimationEnabled,
        previewOverlayOpacity: stored.previewOverlayOpacity,
        previewToolbarOpacity: stored.previewToolbarOpacity,
        previewFilmstripOpacity: stored.previewFilmstripOpacity,
        previewFilmstripHeight: stored.previewFilmstripHeight,
        rawViewMode: stored.rawViewMode,
      );
    });
  }

  Future<void> _updateCrossAxisCount(int delta) async {
    final newCount = (_crossAxisCount + delta).clamp(1, 10);
    if (newCount == _crossAxisCount) return;

    setState(() {
      _crossAxisCount = newCount;
    });
    await const PreferencesRepository().saveCrossAxisCount(newCount);
  }

  void _handleGridPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !isZoomModifierPressed()) {
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
    _gridZoomResetTimer?.cancel();
    _gridZoomResetTimer =
        Timer(kGridZoomScrollResetDelay, _gridZoom.resetScroll);

    final columnChange = _gridZoom.addScrollDelta(delta);
    if (columnChange != 0) {
      unawaited(_updateCrossAxisCount(columnChange));
    }
  }

  void _handleGridTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _gridZoom.beginTrackpadPinch();
  }

  void _handleGridTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final columnChange = _gridZoom.addTrackpadScale(event.scale);
    if (columnChange != 0) {
      unawaited(_updateCrossAxisCount(columnChange));
    }
  }

  Future<void> _persistGridAspectRatio(GridAspectRatio ratio) =>
      const PreferencesRepository().saveGridAspectRatio(ratio);

  Future<void> _persistPageSwitchAnimationEnabled(bool enabled) =>
      const PreferencesRepository().savePageSwitchAnimationEnabled(enabled);

  Future<void> _persistPreviewOverlayOpacity(double opacity) =>
      const PreferencesRepository().savePreviewOverlayOpacity(opacity);

  Future<void> _persistPreviewToolbarOpacity(double opacity) =>
      const PreferencesRepository().savePreviewToolbarOpacity(opacity);

  Future<void> _persistPreviewFilmstripOpacity(double opacity) =>
      const PreferencesRepository().savePreviewFilmstripOpacity(opacity);

  Future<void> _persistPreviewFilmstripHeight(double height) =>
      const PreferencesRepository().savePreviewFilmstripHeight(height);

  Future<void> _persistRawViewMode(RawViewMode mode) =>
      const PreferencesRepository().saveRawViewMode(mode);

  void _updateSettings(ViewerSettings settings) {
    final cacheSizeChanged = _settings.maxCacheSize != settings.maxCacheSize;
    final appLanguageChanged = _settings.appLanguage != settings.appLanguage;
    final gridAspectRatioChanged =
        _settings.gridAspectRatio != settings.gridAspectRatio;
    final pageSwitchAnimationChanged = _settings.pageSwitchAnimationEnabled !=
        settings.pageSwitchAnimationEnabled;
    final previewOverlayOpacityChanged =
        _settings.previewOverlayOpacity != settings.previewOverlayOpacity;
    final previewToolbarOpacityChanged =
        _settings.previewToolbarOpacity != settings.previewToolbarOpacity;
    final previewFilmstripOpacityChanged =
        _settings.previewFilmstripOpacity != settings.previewFilmstripOpacity;
    final previewFilmstripHeightChanged =
        _settings.previewFilmstripHeight != settings.previewFilmstripHeight;
    final rawViewModeChanged = _settings.rawViewMode != settings.rawViewMode;

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
    if (previewOverlayOpacityChanged) {
      unawaited(
        _persistPreviewOverlayOpacity(
          settings.previewOverlayOpacity,
        ),
      );
    }
    if (previewToolbarOpacityChanged) {
      unawaited(_persistPreviewToolbarOpacity(settings.previewToolbarOpacity));
    }
    if (previewFilmstripOpacityChanged) {
      unawaited(
          _persistPreviewFilmstripOpacity(settings.previewFilmstripOpacity));
    }
    if (previewFilmstripHeightChanged) {
      unawaited(
          _persistPreviewFilmstripHeight(settings.previewFilmstripHeight));
    }
    if (rawViewModeChanged) {
      unawaited(_persistRawViewMode(settings.rawViewMode));
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

  Future<void> _refreshWindowsContextMenuAfterFirstFrame() async {
    if (!Platform.isWindows) return;
    await (widget.desktopWindowReady ??
        WidgetsBinding.instance.waitUntilFirstFrameRasterized);
    if (!mounted) return;
    await _refreshWindowsContextMenuState();
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

  Future<void> _refreshFileAssociationState() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      return;
    }

    try {
      final values = await fileAssociationChannel
          .invokeMapMethod<String, dynamic>('getFileAssociationState');
      if (!mounted) return;
      setState(() {
        _settings = _settings.copyWith(
          fileAssociations: FileAssociationSettings.fromPlatformMap(values),
        );
      });
    } on MissingPluginException {
      // Ignore when file association integration is not implemented.
    } on PlatformException {
      // Ignore transient platform integration failures at startup.
    }
  }

  Future<FileAssociationSettings> _getFileAssociationSettings() async {
    final values = await fileAssociationChannel
        .invokeMapMethod<String, dynamic>('getFileAssociationState');
    return FileAssociationSettings.fromPlatformMap(values);
  }

  Future<WindowsContextMenuSettings> _getWindowsContextMenuSettings() async {
    final values = await windowsShellChannel.invokeMapMethod<String, dynamic>(
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
      final values = await windowsShellChannel.invokeMapMethod<String, dynamic>(
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

  Future<FileAssociationSettings> _setFileAssociations(
    Set<String> extensions,
  ) async {
    try {
      final values = await fileAssociationChannel
          .invokeMapMethod<String, dynamic>('setFileAssociations', {
        'extensions': extensions.toList(growable: false),
      });
      final nextState = FileAssociationSettings.fromPlatformMap(values);
      if (mounted) {
        setState(() {
          _settings = _settings.copyWith(fileAssociations: nextState);
        });
      }
      return nextState;
    } on PlatformException catch (error) {
      throw Exception(error.message ?? 'Unknown file association error');
    } on MissingPluginException {
      throw Exception('File association integration is not supported');
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
      allowedExtensions: supportedExtensions
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
    if (!Platform.isMacOS && !Platform.isWindows && !Platform.isLinux) {
      return;
    }

    desktopOpenChannel.setMethodCallHandler((call) async {
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
      final windowReady = widget.desktopWindowReady;
      if (windowReady != null) await windowReady;
      if (!mounted) return;
      if (Platform.isLinux) {
        final initialPaths = Platform.executableArguments;
        if (initialPaths.isNotEmpty) {
          await _handleIncomingPaths(initialPaths);
        }
        return;
      }

      final initialPaths =
          await desktopOpenChannel.invokeListMethod<String>('getInitialPaths');
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
      final directoryFiles = <MediaFile>[];
      try {
        for (final directory in directories) {
          directoryFiles.addAll(_listRawFilesInDirectory(directory));
        }
      } on FileSystemException catch (error) {
        _showDirectoryLoadError(error);
        return;
      }
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

    final shouldOpenSingleFile = files.length == 1;
    final shouldReplaceCurrent =
        _openedSourceKind != _OpenedSourceKind.files || shouldOpenSingleFile;
    final nextFiles = shouldReplaceCurrent
        ? files
        : _deduplicateMediaFiles([..._files, ...files]);

    _applyOpenedFiles(
      files: nextFiles,
      sourceKind: _OpenedSourceKind.files,
      clearCache: shouldReplaceCurrent,
      deferredDirectoryPath:
          shouldOpenSingleFile ? path.dirname(files.single.path) : null,
    );

    if (shouldOpenSingleFile) {
      _scheduleSingleFilePreview(files.single.path);
    }
  }

  void _applyOpenedFiles({
    required List<MediaFile> files,
    required _OpenedSourceKind sourceKind,
    required bool clearCache,
    String? openedDirectoryPath,
    int? openedDirectoryCount,
    String? deferredDirectoryPath,
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
      _deferredDirectoryPath = deferredDirectoryPath;
      _files = files;
    });
  }

  void _scheduleSingleFilePreview(String filePath) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
        return;
      }
      if (_files.length != 1 || _files.single.path != filePath) {
        return;
      }
      _openPreview(
        mediaGroups: buildAdaptiveMediaGroups(_files),
        initialIndex: 0,
        deferDirectoryLoad: _deferredDirectoryPath != null,
      );
    });
  }

  Future<List<MediaGroup>?> _loadDeferredDirectoryForPreview() async {
    final directoryPath = _deferredDirectoryPath;
    if (directoryPath == null) {
      return buildAdaptiveMediaGroups(_files);
    }

    final loadedDirectory = await _loadDeferredDirectoryFiles(directoryPath);
    if (loadedDirectory == null) {
      return null;
    }
    final mediaGroups = buildAdaptiveMediaGroups(loadedDirectory.files);
    if (mediaGroups.isEmpty) {
      return null;
    }
    _applyOpenedFiles(
      files: loadedDirectory.files,
      sourceKind: _OpenedSourceKind.folder,
      clearCache: false,
      openedDirectoryPath: loadedDirectory.path,
      openedDirectoryCount: 1,
    );
    return mediaGroups;
  }

  Future<void> _loadDeferredDirectoryAfterClose() async {
    if (_deferredDirectoryPath == null) return;
    final directoryPath = _deferredDirectoryPath!;
    try {
      final loadedDirectory = await _loadDeferredDirectoryFiles(directoryPath);
      if (loadedDirectory == null) {
        return;
      }
      _applyOpenedFiles(
        files: loadedDirectory.files,
        sourceKind: _OpenedSourceKind.folder,
        clearCache: false,
        openedDirectoryPath: loadedDirectory.path,
        openedDirectoryCount: 1,
      );
    } catch (error) {
      _showDirectoryLoadError(error);
    }
  }

  Future<_LoadedDirectory?> _loadDeferredDirectoryFiles(
    String directoryPath,
  ) async {
    try {
      return _LoadedDirectory(
        path: directoryPath,
        files: _listRawFilesInDirectory(directoryPath),
      );
    } on FileSystemException {
      if (!Platform.isMacOS || !mounted) {
        rethrow;
      }

      final l10n = AppLocalizations.of(context);
      final selectedDirectory = await macOSDirectoryAccessChannel
          .invokeMethod<String>('selectDirectory', {
        'title': l10n?.grantDirectoryAccessDialogTitle,
        'initialDirectory': directoryPath,
      });
      if (selectedDirectory == null) {
        return null;
      }
      final resolvedDirectory =
          path.normalize(path.absolute(selectedDirectory));
      return _LoadedDirectory(
        path: resolvedDirectory,
        files: _listRawFilesInDirectory(resolvedDirectory),
      );
    }
  }

  void _showDirectoryLoadError(Object error) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.loadDirectoryFailedMessage('$error'))),
      );
  }

  void _openPreview({
    required List<MediaGroup> mediaGroups,
    required int initialIndex,
    required bool deferDirectoryLoad,
  }) {
    if (mediaGroups.isEmpty || !mounted) return;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final totalPadding = 16.0 + (_crossAxisCount - 1) * 8.0;
    final cellWidth = (screenWidth - totalPadding) / _crossAxisCount;
    final thumbnailResizeWidth =
        bucketDecodeWidth((cellWidth * dpr).clamp(100.0, 800.0));

    Navigator.push<void>(
      context,
      PageRouteBuilder(
        transitionDuration: kImagePreviewOpenTransitionDuration,
        reverseTransitionDuration: kImagePreviewCloseTransitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) {
          return ExcludeSemantics(
            child: ImagePreviewPage(
              mediaGroups: mediaGroups,
              initialIndex: initialIndex,
              thumbnailResizeWidth: thumbnailResizeWidth,
              imageStore: _imageStore,
              timestampRepository: _timestampRepository,
              initialSettings: _settings,
              onLoadDirectory:
                  deferDirectoryLoad ? _loadDeferredDirectoryForPreview : null,
              onRawViewModeChanged: (mode) => _updateSettings(
                _settings.copyWith(rawViewMode: mode),
              ),
              onPreviewFilmstripHeightChanged: (height) => _updateSettings(
                _settings.copyWith(previewFilmstripHeight: height),
              ),
              onClose: () {
                Navigator.pop(context);
                unawaited(_loadDeferredDirectoryAfterClose());
              },
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
  }

  List<MediaFile> _listRawFilesInDirectory(String directoryPath) =>
      listMediaFilesInDirectory(directoryPath);

  List<MediaFile> _deduplicateMediaFiles(Iterable<MediaFile> files) =>
      deduplicateMediaFiles(files);

  MediaFile? _mediaFileFromPath(String filePath) => mediaFileFromPath(filePath);

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
    return MediaThumbnailTile(
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
        _openPreview(
          mediaGroups: mediaGroups,
          initialIndex: index,
          deferDirectoryLoad: false,
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

    final scrollable = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification ||
            notification is UserScrollNotification) {
          _prefetchGalleryAround(
            mediaGroups,
            thumbnailResizeWidth,
            notification.metrics,
          );
        }
        return false;
      },
      child: grid,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        scrollable,
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

  void _prefetchGalleryAround(
    List<MediaGroup> mediaGroups,
    int thumbnailResizeWidth,
    ScrollMetrics metrics,
  ) {
    if (mediaGroups.isEmpty || metrics.maxScrollExtent <= 0) return;
    final fraction = (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);
    final anchor = (fraction * (mediaGroups.length - 1)).round();
    if ((anchor - _lastGalleryPrefetchAnchor).abs() < _crossAxisCount) return;
    _lastGalleryPrefetchAnchor = anchor;

    final start = math.max(0, anchor - _crossAxisCount * 2);
    final end = math.min(
      mediaGroups.length,
      anchor + _crossAxisCount * 4,
    );
    for (var index = start; index < end; index++) {
      final mediaFile = mediaGroups[index].primary;
      if (!mediaFile.isRaw) {
        precacheImage(
          ResizeImage(FileImage(File(mediaFile.path)),
              width: thumbnailResizeWidth),
          context,
        );
        continue;
      }
      unawaited(_imageStore
          .load(
            mediaFile.path,
            RawLayer.thumbnail,
            targetWidth: thumbnailResizeWidth,
            priority: TaskPriority.low,
          )
          .then((image) => image?.dispose()));
    }
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
            DesktopCommandBar(
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
                        ? EmptyGallery(
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
                    child: ThumbnailSizeControls(
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
            GalleryStatusBar(
              itemCountLabel: l10n.galleryItemCount(visibleMediaGroups.length),
              gridColumnsLabel: l10n.gridColumnsTooltip(_crossAxisCount),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSettings() async {
    await Future.wait<void>([
      _refreshWindowsContextMenuState(),
      _refreshFileAssociationState(),
    ]);
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
              onFileAssociationsChanged:
                  Platform.isMacOS ? _setFileAssociations : null,
              onOpenDefaultAppsSettings: Platform.isWindows
                  ? () => fileAssociationChannel
                      .invokeMethod<void>('openDefaultAppsSettings')
                  : null,
              onRefreshFileAssociations:
                  (Platform.isWindows || Platform.isMacOS)
                      ? _getFileAssociationSettings
                      : null,
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
