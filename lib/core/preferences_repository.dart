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

  /// macOS security-scoped bookmark that restores sandbox access to [path]
  /// in a later launch. Null on other platforms and for entries saved before
  /// bookmarks were recorded.
  final String? bookmark;

  const RecentOpenItem({
    required this.path,
    required this.isDirectory,
    this.bookmark,
  });

  Map<String, Object> toJson() => {
        'path': path,
        'isDirectory': isDirectory,
        if (bookmark != null) 'bookmark': bookmark!,
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

    final bookmark = value['bookmark'];
    return RecentOpenItem(
      path: path,
      isDirectory: isDirectory,
      bookmark: bookmark is String && bookmark.isNotEmpty ? bookmark : null,
    );
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
  final bool directoryBrowsingEnabled;
  final bool hotFolderEnabled;
  final int crossAxisCount;
  final GridAspectRatio? gridAspectRatio;
  final GridLabelPlacement gridLabelPlacement;
  final double gridCornerRadius;
  final double gridSpacing;
  final bool useHalfSizeRawDecode;
  final int maxCacheSize;
  final TimeDisplaySource timeDisplaySource;
  final AppLanguage appLanguage;
  final bool pageSwitchAnimationEnabled;
  final bool longPressLivePhotoEnabled;
  final bool previewAutoHideControls;
  final double previewFilmstripHeight;
  final bool showPreviewFilmstrip;
  final bool showThumbnailRatings;
  final bool hideUnratedRatings;
  final bool showPreviewOverview;
  final ExifSidebarSettings exifSidebar;
  final RawViewMode? rawViewMode;
  final MediaSortOrder mediaSortOrder;

  const StoredViewPreferences({
    this.directoryBrowsingEnabled = false,
    this.hotFolderEnabled = false,
    required this.crossAxisCount,
    required this.gridAspectRatio,
    required this.gridLabelPlacement,
    required this.gridCornerRadius,
    required this.gridSpacing,
    required this.useHalfSizeRawDecode,
    required this.maxCacheSize,
    required this.timeDisplaySource,
    required this.appLanguage,
    required this.pageSwitchAnimationEnabled,
    this.longPressLivePhotoEnabled = false,
    this.previewAutoHideControls = true,
    required this.previewFilmstripHeight,
    required this.showPreviewFilmstrip,
    this.showThumbnailRatings = true,
    this.hideUnratedRatings = true,
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
  static const String _gridLabelPlacement = 'grid_label_placement';
  static const String _gridCornerRadius = 'grid_corner_radius';
  static const String _gridSpacing = 'grid_spacing';
  static const String _useHalfSizeRawDecode = 'use_half_size_raw_decode';
  static const String _maxCacheSize = 'max_cache_size';
  static const String _timeDisplaySource = 'time_display_source';
  static const String _appLanguage = 'app_language';
  static const String _pageSwitchAnimationEnabled =
      'page_switch_animation_enabled';
  static const String _longPressLivePhotoEnabled =
      'long_press_live_photo_enabled';
  static const String _previewAutoHideControls = 'preview_auto_hide_controls';
  static const String _previewFilmstripHeight = 'preview_filmstrip_height';
  static const String _showPreviewFilmstrip = 'show_preview_filmstrip';
  static const String _showThumbnailRatings = 'show_thumbnail_ratings';
  static const String _directoryBrowsingEnabled = 'directory_browsing_enabled';
  static const String _hotFolderEnabled = 'hot_folder_enabled';

  Future<void> saveDirectoryBrowsingEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_directoryBrowsingEnabled, enabled);
  }

  Future<void> saveHotFolderEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hotFolderEnabled, enabled);
  }

  Future<void> saveLongPressLivePhotoEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_longPressLivePhotoEnabled, enabled);
  }

  static const String _hideUnratedRatings = 'hide_unrated_ratings';
  static const String _showPreviewOverview = 'show_preview_overview';
  static const String _showExifSidebar = 'show_exif_sidebar';
  static const String _exifSidebarWidth = 'exif_sidebar_width';
  static const String _exifExpandedSections = 'exif_expanded_sections';
  static const String _rawViewMode = 'raw_view_mode';
  static const String _mediaSortOrder = 'media_sort_order';
  static const String _recentOpenItems = 'recent_open_items';

  /// Resting-opacity settings superseded by [_previewAutoHideControls]: the
  /// preview's controls now hide completely instead of resting translucent
  /// over the photo. Only ever removed, so stale values do not linger.
  static const List<String> _legacyPreviewOpacityKeys = [
    'preview_overlay_opacity',
    'preview_toolbar_opacity',
    'preview_filmstrip_opacity',
    'preview_overlay_auto_transparency_enabled',
  ];

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
    for (final key in _legacyPreviewOpacityKeys) {
      if (prefs.containsKey(key)) await prefs.remove(key);
    }
    return StoredViewPreferences(
      crossAxisCount:
          prefs.getInt(_gridCrossAxisCount) ?? kDefaultGridCrossAxisCount,
      gridAspectRatio:
          GridAspectRatio.values.asNameMap()[prefs.getString(_gridAspectRatio)],
      gridLabelPlacement: GridLabelPlacement.values
              .asNameMap()[prefs.getString(_gridLabelPlacement)] ??
          GridLabelPlacement.overlay,
      gridCornerRadius:
          (prefs.getDouble(_gridCornerRadius) ?? kDefaultGridCornerRadius)
              .clamp(kMinGridCornerRadius, kMaxGridCornerRadius)
              .toDouble(),
      gridSpacing: (prefs.getDouble(_gridSpacing) ?? kDefaultGridSpacing)
          .clamp(kMinGridSpacing, kMaxGridSpacing)
          .toDouble(),
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
      longPressLivePhotoEnabled:
          prefs.getBool(_longPressLivePhotoEnabled) ?? false,
      previewAutoHideControls: prefs.getBool(_previewAutoHideControls) ?? true,
      previewFilmstripHeight: normalizePreviewFilmstripHeight(
        prefs.getDouble(_previewFilmstripHeight) ?? kPreviewFilmstripHeight,
      ),
      showPreviewFilmstrip: prefs.getBool(_showPreviewFilmstrip) ?? true,
      showThumbnailRatings: prefs.getBool(_showThumbnailRatings) ?? true,
      directoryBrowsingEnabled:
          prefs.getBool(_directoryBrowsingEnabled) ?? false,
      hotFolderEnabled: prefs.getBool(_hotFolderEnabled) ?? false,
      hideUnratedRatings: prefs.getBool(_hideUnratedRatings) ?? true,
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

  Future<void> saveCrossAxisCount(int count) async {
    final prefs = await _prefs;
    await prefs.setInt(_gridCrossAxisCount, count);
  }

  Future<void> saveGridAspectRatio(GridAspectRatio ratio) async {
    final prefs = await _prefs;
    await prefs.setString(_gridAspectRatio, ratio.name);
  }

  Future<void> saveGridLabelPlacement(GridLabelPlacement placement) async {
    final prefs = await _prefs;
    await prefs.setString(_gridLabelPlacement, placement.name);
  }

  Future<void> saveGridCornerRadius(double radius) async {
    final prefs = await _prefs;
    await prefs.setDouble(
      _gridCornerRadius,
      radius.clamp(kMinGridCornerRadius, kMaxGridCornerRadius).toDouble(),
    );
  }

  Future<void> saveGridSpacing(double spacing) async {
    final prefs = await _prefs;
    await prefs.setDouble(
      _gridSpacing,
      spacing.clamp(kMinGridSpacing, kMaxGridSpacing).toDouble(),
    );
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

  Future<void> savePreviewAutoHideControls(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_previewAutoHideControls, enabled);
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

  Future<void> saveShowThumbnailRatings(bool show) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showThumbnailRatings, show);
  }

  Future<void> saveShowPreviewOverview(bool show) async {
    final prefs = await _prefs;
    await prefs.setBool(_showPreviewOverview, show);
  }

  Future<void> saveHideUnratedRatings(bool hide) async {
    final prefs = await _prefs;
    await prefs.setBool(_hideUnratedRatings, hide);
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
