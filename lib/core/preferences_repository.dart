import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../media_sort.dart';
import '../settings_page.dart';
import 'exif_sidebar_settings.dart';
import 'preview_filmstrip_size.dart';
import 'raw_view_mode.dart';

/// Default column count for the thumbnail grid.
const int kDefaultGridCrossAxisCount = 4;

/// Bounds on the thumbnail grid column count.
const int kMinGridCrossAxisCount = 1;
const int kMaxGridCrossAxisCount = 10;

/// Maximum number of files and folders retained in the recent-open list.
const int kMaxRecentOpenItems = 10;

/// A file or folder that can be reopened from the gallery home screen.
class RecentOpenItem {
  final String path;
  final bool isDirectory;

  const RecentOpenItem({
    required this.path,
    required this.isDirectory,
  });

  Map<String, Object> toJson() => {
        'path': path,
        'isDirectory': isDirectory,
      };

  static RecentOpenItem? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final path = value['path'];
    final isDirectory = value['isDirectory'];
    if (path is! String || path.isEmpty || isDirectory is! bool) {
      return null;
    }

    return RecentOpenItem(path: path, isDirectory: isDirectory);
  }
}

/// Persisted window geometry for desktop platforms.
class WindowGeometry {
  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool isMaximized;

  const WindowGeometry({
    required this.width,
    required this.height,
    this.x,
    this.y,
    this.isMaximized = false,
  });

  bool get hasPosition => x != null && y != null;
}

/// View preferences restored at startup.
class StoredViewPreferences {
  final int crossAxisCount;
  final GridAspectRatio? gridAspectRatio;
  final bool useHalfSizeRawDecode;
  final int maxCacheSize;
  final TimeDisplaySource timeDisplaySource;
  final AppLanguage appLanguage;
  final bool pageSwitchAnimationEnabled;
  final double previewOverlayOpacity;
  final double previewToolbarOpacity;
  final double previewFilmstripOpacity;
  final double previewFilmstripHeight;
  final bool showPreviewFilmstrip;
  final bool showPreviewOverview;
  final ExifSidebarSettings exifSidebar;
  final RawViewMode? rawViewMode;
  final MediaSortOrder mediaSortOrder;

  const StoredViewPreferences({
    required this.crossAxisCount,
    required this.gridAspectRatio,
    required this.useHalfSizeRawDecode,
    required this.maxCacheSize,
    required this.timeDisplaySource,
    required this.appLanguage,
    required this.pageSwitchAnimationEnabled,
    required this.previewOverlayOpacity,
    required this.previewToolbarOpacity,
    required this.previewFilmstripOpacity,
    required this.previewFilmstripHeight,
    required this.showPreviewFilmstrip,
    required this.showPreviewOverview,
    this.exifSidebar = const ExifSidebarSettings(),
    required this.rawViewMode,
    required this.mediaSortOrder,
  });
}

/// Typed access to every persisted preference.
///
/// Keys live here and nowhere else: a mistyped key literal fails silently at
/// runtime, dropping the setting rather than raising, so there is exactly one
/// place each key is spelled.
class PreferencesRepository {
  const PreferencesRepository();

  // Window geometry.
  static const String _windowWidth = 'window_width';
  static const String _windowHeight = 'window_height';
  static const String _windowX = 'window_x';
  static const String _windowY = 'window_y';
  static const String _windowMaximized = 'window_maximized';

  // View preferences.
  static const String _gridCrossAxisCount = 'grid_cross_axis_count';
  static const String _gridAspectRatio = 'grid_aspect_ratio';
  static const String _useHalfSizeRawDecode = 'use_half_size_raw_decode';
  static const String _maxCacheSize = 'max_cache_size';
  static const String _timeDisplaySource = 'time_display_source';
  static const String _appLanguage = 'app_language';
  static const String _pageSwitchAnimationEnabled =
      'page_switch_animation_enabled';
  static const String _previewOverlayOpacity = 'preview_overlay_opacity';
  static const String _previewToolbarOpacity = 'preview_toolbar_opacity';
  static const String _previewFilmstripOpacity = 'preview_filmstrip_opacity';
  static const String _previewFilmstripHeight = 'preview_filmstrip_height';
  static const String _showPreviewFilmstrip = 'show_preview_filmstrip';
  static const String _showPreviewOverview = 'show_preview_overview';
  static const String _showExifSidebar = 'show_exif_sidebar';
  static const String _exifSidebarWidth = 'exif_sidebar_width';
  static const String _exifExpandedSections = 'exif_expanded_sections';
  static const String _rawViewMode = 'raw_view_mode';
  static const String _mediaSortOrder = 'media_sort_order';
  static const String _recentOpenItems = 'recent_open_items';

  /// Superseded by [_previewOverlayOpacity]. Read only, to migrate installs
  /// that predate the continuous opacity slider.
  static const String _legacyPreviewOverlayAutoTransparency =
      'preview_overlay_auto_transparency_enabled';

  static const double _defaultWindowWidth = 1024.0;
  static const double _defaultWindowHeight = 768.0;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // --- Window geometry ---

  Future<WindowGeometry> loadWindowGeometry() async {
    final prefs = await _prefs;
    return WindowGeometry(
      width: prefs.getDouble(_windowWidth) ?? _defaultWindowWidth,
      height: prefs.getDouble(_windowHeight) ?? _defaultWindowHeight,
      x: prefs.getDouble(_windowX),
      y: prefs.getDouble(_windowY),
      isMaximized: prefs.getBool(_windowMaximized) ?? false,
    );
  }

  Future<void> saveWindowBounds({
    required double width,
    required double height,
    required double x,
    required double y,
  }) async {
    final prefs = await _prefs;
    await prefs.setDouble(_windowWidth, width);
    await prefs.setDouble(_windowHeight, height);
    await prefs.setDouble(_windowX, x);
    await prefs.setDouble(_windowY, y);
  }

  Future<void> saveWindowMaximized(bool isMaximized) async {
    final prefs = await _prefs;
    await prefs.setBool(_windowMaximized, isMaximized);
  }

  // --- View preferences ---

  Future<StoredViewPreferences> loadViewPreferences() async {
    final prefs = await _prefs;
    final overlayOpacity = resolvePreviewOverlayOpacity(
      storedOpacity: prefs.getDouble(_previewOverlayOpacity),
      legacyAutoTransparencyEnabled:
          prefs.getBool(_legacyPreviewOverlayAutoTransparency),
    );
    return StoredViewPreferences(
      crossAxisCount:
          prefs.getInt(_gridCrossAxisCount) ?? kDefaultGridCrossAxisCount,
      gridAspectRatio:
          GridAspectRatio.values.asNameMap()[prefs.getString(_gridAspectRatio)],
      useHalfSizeRawDecode: prefs.getBool(_useHalfSizeRawDecode) ?? true,
      maxCacheSize: prefs.getInt(_maxCacheSize) ?? 512,
      timeDisplaySource: TimeDisplaySource.values
              .asNameMap()[prefs.getString(_timeDisplaySource)] ??
          TimeDisplaySource.capturedAt,
      appLanguage:
          AppLanguage.values.asNameMap()[prefs.getString(_appLanguage)] ??
              AppLanguage.system,
      pageSwitchAnimationEnabled:
          prefs.getBool(_pageSwitchAnimationEnabled) ?? true,
      previewOverlayOpacity: overlayOpacity,
      previewToolbarOpacity: await _loadPreviewBarOpacity(
        prefs,
        _previewToolbarOpacity,
        overlayOpacity,
      ),
      previewFilmstripOpacity: await _loadPreviewBarOpacity(
        prefs,
        _previewFilmstripOpacity,
        overlayOpacity,
      ),
      previewFilmstripHeight: normalizePreviewFilmstripHeight(
        prefs.getDouble(_previewFilmstripHeight) ?? kPreviewFilmstripHeight,
      ),
      showPreviewFilmstrip: prefs.getBool(_showPreviewFilmstrip) ?? true,
      showPreviewOverview: prefs.getBool(_showPreviewOverview) ?? true,
      exifSidebar: ExifSidebarSettings(
        visible: prefs.getBool(_showExifSidebar) ?? false,
        width: normalizeExifSidebarWidth(
          prefs.getDouble(_exifSidebarWidth) ?? kDefaultExifSidebarWidth,
        ),
        expandedSections: Set.unmodifiable({
          for (final name
              in prefs.getStringList(_exifExpandedSections) ?? <String>[])
            if (ExifSection.values.asNameMap()[name]
                case final ExifSection section)
              section,
        }),
      ),
      rawViewMode:
          RawViewMode.values.asNameMap()[prefs.getString(_rawViewMode)],
      mediaSortOrder:
          MediaSortOrder.values.asNameMap()[prefs.getString(_mediaSortOrder)] ??
              defaultMediaSortOrder,
    );
  }

  Future<double> _loadPreviewBarOpacity(
    SharedPreferences prefs,
    String key,
    double fallback,
  ) async {
    final stored = prefs.getDouble(key);
    if (stored == null) {
      // Migrate once so later tool-opacity changes cannot change either bar.
      await prefs.setDouble(key, fallback);
    }
    return (stored ?? fallback)
        .clamp(kMinPreviewOverlayOpacity, kMaxPreviewOverlayOpacity)
        .toDouble();
  }

  /// Resolves the overlay opacity, migrating the superseded boolean setting.
  ///
  /// Before the opacity slider existed the setting was a single on/off flag.
  /// Explicitly turning auto-transparency *off* meant "keep overlays fully
  /// opaque", so that install migrates to the maximum rather than the default.
  /// Every other legacy state (on, or never set) migrates to the default.
  static double resolvePreviewOverlayOpacity({
    required double? storedOpacity,
    required bool? legacyAutoTransparencyEnabled,
  }) {
    return (storedOpacity ??
            (legacyAutoTransparencyEnabled == false
                ? kMaxPreviewOverlayOpacity
                : kDefaultPreviewOverlayOpacity))
        .clamp(kMinPreviewOverlayOpacity, kMaxPreviewOverlayOpacity)
        .toDouble();
  }

  Future<void> saveCrossAxisCount(int count) async {
    final prefs = await _prefs;
    await prefs.setInt(_gridCrossAxisCount, count);
  }

  Future<void> saveGridAspectRatio(GridAspectRatio ratio) async {
    final prefs = await _prefs;
    await prefs.setString(_gridAspectRatio, ratio.name);
  }

  Future<void> saveUseHalfSizeRawDecode(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_useHalfSizeRawDecode, enabled);
  }

  Future<void> saveMaxCacheSize(int sizeInMb) async {
    final prefs = await _prefs;
    await prefs.setInt(_maxCacheSize, sizeInMb);
  }

  Future<void> saveTimeDisplaySource(TimeDisplaySource source) async {
    final prefs = await _prefs;
    await prefs.setString(_timeDisplaySource, source.name);
  }

  Future<void> saveAppLanguage(AppLanguage language) async {
    final prefs = await _prefs;
    await prefs.setString(_appLanguage, language.name);
  }

  Future<void> savePageSwitchAnimationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_pageSwitchAnimationEnabled, enabled);
  }

  Future<void> savePreviewOverlayOpacity(double opacity) async {
    final prefs = await _prefs;
    await prefs.setDouble(_previewOverlayOpacity, opacity);
  }

  Future<void> savePreviewToolbarOpacity(double opacity) async {
    final prefs = await _prefs;
    await prefs.setDouble(_previewToolbarOpacity, opacity);
  }

  Future<void> savePreviewFilmstripOpacity(double opacity) async {
    final prefs = await _prefs;
    await prefs.setDouble(_previewFilmstripOpacity, opacity);
  }

  Future<void> saveRawViewMode(RawViewMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_rawViewMode, mode.name);
  }

  Future<void> saveMediaSortOrder(MediaSortOrder sortOrder) async {
    final prefs = await _prefs;
    await prefs.setString(_mediaSortOrder, sortOrder.name);
  }

  Future<void> savePreviewFilmstripHeight(double height) async {
    final prefs = await _prefs;
    await prefs.setDouble(
      _previewFilmstripHeight,
      normalizePreviewFilmstripHeight(height),
    );
  }

  Future<void> saveShowPreviewFilmstrip(bool show) async {
    final prefs = await _prefs;
    await prefs.setBool(_showPreviewFilmstrip, show);
  }

  Future<void> saveShowPreviewOverview(bool show) async {
    final prefs = await _prefs;
    await prefs.setBool(_showPreviewOverview, show);
  }

  Future<void> saveExifSidebarSettings(ExifSidebarSettings settings) async {
    final prefs = await _prefs;
    await Future.wait([
      prefs.setBool(_showExifSidebar, settings.visible),
      prefs.setDouble(
          _exifSidebarWidth, normalizeExifSidebarWidth(settings.width)),
      prefs.setStringList(
          _exifExpandedSections,
          settings.expandedSections.map((section) => section.name).toList()
            ..sort()),
    ]);
  }

  // --- Recent opens ---
  Future<List<RecentOpenItem>> loadRecentOpenItems() async {
    final prefs = await _prefs;
    final storedItems = prefs.getStringList(_recentOpenItems) ?? const [];
    final recentItems = <RecentOpenItem>[];

    for (final storedItem in storedItems) {
      try {
        final item = RecentOpenItem.fromJson(jsonDecode(storedItem));
        if (item != null) {
          recentItems.add(item);
        }
      } on FormatException {
        // Ignore a corrupt entry while keeping the remaining history usable.
      }
    }

    return recentItems.take(kMaxRecentOpenItems).toList(growable: false);
  }

  Future<void> saveRecentOpenItems(List<RecentOpenItem> items) async {
    final prefs = await _prefs;
    await prefs.setStringList(
      _recentOpenItems,
      items
          .take(kMaxRecentOpenItems)
          .map((item) => jsonEncode(item.toJson()))
          .toList(growable: false),
    );
  }
}
