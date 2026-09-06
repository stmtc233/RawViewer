import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_sidebar_settings.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sidebar defaults to closed with collapsed sections', () async {
    final settings =
        (await const PreferencesRepository().loadViewPreferences()).exifSidebar;
    expect(settings.visible, isFalse);
    expect(settings.width, 340);
    expect(settings.expandedSections, isEmpty);
  });

  test('round-trips all sidebar settings across unrelated changes', () async {
    const repo = PreferencesRepository();
    await repo.saveExifSidebarSettings(const ExifSidebarSettings(
      visible: true,
      width: 456,
      expandedSections: {ExifSection.image, ExifSection.gps},
    ));
    final settings = ViewerSettings(
            exifSidebar: (await repo.loadViewPreferences()).exifSidebar)
        .copyWith(previewToolbarOpacity: 0.8);
    expect(settings.exifSidebar.visible, isTrue);
    expect(settings.exifSidebar.width, 456);
    expect(settings.exifSidebar.expandedSections,
        {ExifSection.image, ExifSection.gps});
    await repo.savePreviewToolbarOpacity(settings.previewToolbarOpacity);
    await repo
        .saveExifSidebarSettings(settings.exifSidebar.copyWith(visible: false));
    final stored = (await repo.loadViewPreferences()).exifSidebar;
    expect(stored.visible, isFalse);
    expect(stored.width, 456);
    expect(stored.expandedSections, {ExifSection.image, ExifSection.gps});
  });

  test('normalizes stored widths and ignores unknown section names', () async {
    for (final (width, expected) in [
      (1.0, 280.0),
      (9999.0, 640.0),
      (double.nan, 340.0),
      (double.infinity, 340.0),
    ]) {
      SharedPreferences.setMockInitialValues({
        'exif_sidebar_width': width,
        'exif_expanded_sections': ['file', 'exif', 'unknown'],
      });
      final settings =
          (await const PreferencesRepository().loadViewPreferences())
              .exifSidebar;
      expect(settings.width, expected);
      expect(settings.expandedSections, {ExifSection.file, ExifSection.exif});
    }
  });

  test('clamps display width without changing the preference', () {
    const settings = ExifSidebarSettings(width: 600);
    expect(clampExifSidebarWidth(settings.width, 1200), 600);
    expect(clampExifSidebarWidth(settings.width, 800), 440);
    expect(clampExifSidebarWidth(settings.width, 360), 336);
    expect(clampExifSidebarWidth(280, 360), 280);
    expect(clampExifSidebarWidth(settings.width, 10), 0);
    expect(settings.width, 600);
  });
}
