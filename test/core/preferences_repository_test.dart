import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PreferencesRepository.resolvePreviewOverlayOpacity', () {
    test('uses storedOpacity when present', () {
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: 0.6,
          legacyAutoTransparencyEnabled: null,
        ),
        0.6,
      );
    });

    test('clamps storedOpacity to valid range', () {
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: 0.0,
          legacyAutoTransparencyEnabled: null,
        ),
        kMinPreviewOverlayOpacity,
      );
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: 2.0,
          legacyAutoTransparencyEnabled: null,
        ),
        kMaxPreviewOverlayOpacity,
      );
    });

    test('migrates legacy flag=false to maximum opacity', () {
      // Old installs that explicitly turned auto-transparency OFF wanted
      // opaque overlays; migrate them to the maximum.
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: null,
          legacyAutoTransparencyEnabled: false,
        ),
        kMaxPreviewOverlayOpacity,
      );
    });

    test('migrates legacy flag=true to default opacity', () {
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: null,
          legacyAutoTransparencyEnabled: true,
        ),
        kDefaultPreviewOverlayOpacity,
      );
    });

    test('uses default when both values are absent', () {
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: null,
          legacyAutoTransparencyEnabled: null,
        ),
        kDefaultPreviewOverlayOpacity,
      );
    });

    test('storedOpacity takes precedence over legacy flag', () {
      expect(
        PreferencesRepository.resolvePreviewOverlayOpacity(
          storedOpacity: 0.7,
          legacyAutoTransparencyEnabled: false,
        ),
        0.7,
      );
    });
  });

  group('PreferencesRepository loadViewPreferences', () {
    test('returns defaults when no prefs are stored', () async {
      SharedPreferences.setMockInitialValues({});
      final stored =
          await const PreferencesRepository().loadViewPreferences();
      expect(stored.crossAxisCount, kDefaultGridCrossAxisCount);
      expect(stored.gridAspectRatio, isNull);
      expect(stored.pageSwitchAnimationEnabled, isTrue);
      expect(stored.previewOverlayOpacity, kDefaultPreviewOverlayOpacity);
    });

    test('round-trips grid cross-axis count', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.saveCrossAxisCount(7);
      final stored = await repo.loadViewPreferences();
      expect(stored.crossAxisCount, 7);
    });

    test('round-trips grid aspect ratio', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.saveGridAspectRatio(GridAspectRatio.ratio4x3);
      final stored = await repo.loadViewPreferences();
      expect(stored.gridAspectRatio, GridAspectRatio.ratio4x3);
    });

    test('round-trips page switch animation setting', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.savePageSwitchAnimationEnabled(false);
      final stored = await repo.loadViewPreferences();
      expect(stored.pageSwitchAnimationEnabled, isFalse);
    });

    test('round-trips preview overlay opacity', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.savePreviewOverlayOpacity(0.8);
      final stored = await repo.loadViewPreferences();
      expect(stored.previewOverlayOpacity, closeTo(0.8, 0.001));
    });

    test('migrates legacy auto-transparency-disabled key on first load', () async {
      SharedPreferences.setMockInitialValues({
        'preview_overlay_auto_transparency_enabled': false,
      });
      final stored =
          await const PreferencesRepository().loadViewPreferences();
      expect(stored.previewOverlayOpacity, kMaxPreviewOverlayOpacity);
    });
  });

  group('PreferencesRepository loadWindowGeometry', () {
    test('returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final geometry =
          await const PreferencesRepository().loadWindowGeometry();
      expect(geometry.width, 1024.0);
      expect(geometry.height, 768.0);
      expect(geometry.x, isNull);
      expect(geometry.y, isNull);
      expect(geometry.isMaximized, isFalse);
      expect(geometry.hasPosition, isFalse);
    });

    test('round-trips window bounds', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.saveWindowBounds(
        width: 1280,
        height: 800,
        x: 100,
        y: 200,
      );
      final geometry = await repo.loadWindowGeometry();
      expect(geometry.width, 1280.0);
      expect(geometry.height, 800.0);
      expect(geometry.x, 100.0);
      expect(geometry.y, 200.0);
      expect(geometry.hasPosition, isTrue);
    });

    test('round-trips maximized flag', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.saveWindowMaximized(true);
      final geometry = await repo.loadWindowGeometry();
      expect(geometry.isMaximized, isTrue);
    });
  });
}
