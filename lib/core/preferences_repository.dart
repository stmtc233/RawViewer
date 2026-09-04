import 'package:shared_preferences/shared_preferences.dart';

import '../settings_page.dart';

/// Default column count for the thumbnail grid.
const int kDefaultGridCrossAxisCount = 4;

/// Bounds on the thumbnail grid column count.
const int kMinGridCrossAxisCount = 1;
const int kMaxGridCrossAxisCount = 10;

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
  final bool pageSwitchAnimationEnabled;
  final double previewOverlayOpacity;

  const StoredViewPreferences({
    required this.crossAxisCount,
    required this.gridAspectRatio,
    required this.pageSwitchAnimationEnabled,
    required this.previewOverlayOpacity,
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
  static const String _pageSwitchAnimationEnabled =
      'page_switch_animation_enabled';
  static const String _previewOverlayOpacity = 'preview_overlay_opacity';

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
    return StoredViewPreferences(
      crossAxisCount:
          prefs.getInt(_gridCrossAxisCount) ?? kDefaultGridCrossAxisCount,
      gridAspectRatio:
          GridAspectRatio.values.asNameMap()[prefs.getString(_gridAspectRatio)],
      pageSwitchAnimationEnabled:
          prefs.getBool(_pageSwitchAnimationEnabled) ?? true,
      previewOverlayOpacity: resolvePreviewOverlayOpacity(
        storedOpacity: prefs.getDouble(_previewOverlayOpacity),
        legacyAutoTransparencyEnabled:
            prefs.getBool(_legacyPreviewOverlayAutoTransparency),
      ),
    );
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

  Future<void> savePageSwitchAnimationEnabled(bool enabled) async {
    final prefs = await _prefs;
    await prefs.setBool(_pageSwitchAnimationEnabled, enabled);
  }

  Future<void> savePreviewOverlayOpacity(double opacity) async {
    final prefs = await _prefs;
    await prefs.setDouble(_previewOverlayOpacity, opacity);
  }
}
