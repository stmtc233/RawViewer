import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/core/preview_filmstrip_size.dart';
import 'package:rawviewer/core/raw_view_mode.dart';
import 'package:rawviewer/media_sort.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('hiding unrated badges defaults on and persists independently',
      () async {
    SharedPreferences.setMockInitialValues({});
    const repository = PreferencesRepository();
    expect((await repository.loadViewPreferences()).hideUnratedRatings, isTrue);
    await repository.saveHideUnratedRatings(true);
    await repository.saveShowThumbnailRatings(false);
    final stored = await repository.loadViewPreferences();
    expect(stored.hideUnratedRatings, isTrue);
    final settings =
        ViewerSettings(hideUnratedRatings: stored.hideUnratedRatings);
    expect(settings.copyWith(showThumbnailRatings: false).hideUnratedRatings,
        isTrue);
    expect(settings.copyWith(hideUnratedRatings: false).hideUnratedRatings,
        isFalse);
    await repository.saveHideUnratedRatings(false);
    expect(
        (await repository.loadViewPreferences()).hideUnratedRatings, isFalse);
    expect(
        (await repository.loadViewPreferences()).showThumbnailRatings, isFalse);
  });

  test('thumbnail rating visibility defaults on and persists both states',
      () async {
    SharedPreferences.setMockInitialValues({});
    const repository = PreferencesRepository();
    expect(
        (await repository.loadViewPreferences()).showThumbnailRatings, isTrue);
    await repository.saveShowThumbnailRatings(false);
    final stored = await repository.loadViewPreferences();
    expect(stored.showThumbnailRatings, isFalse);
    final settings =
        ViewerSettings(showThumbnailRatings: stored.showThumbnailRatings);
    expect(settings.copyWith(maxCacheSize: 256).showThumbnailRatings, isFalse);
    await repository.saveShowThumbnailRatings(true);
    expect(
        (await repository.loadViewPreferences()).showThumbnailRatings, isTrue);
  });
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
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.crossAxisCount, kDefaultGridCrossAxisCount);
      expect(stored.gridAspectRatio, isNull);
      expect(stored.useHalfSizeRawDecode, isTrue);
      expect(stored.maxCacheSize, 512);
      expect(stored.timeDisplaySource, TimeDisplaySource.capturedAt);
      expect(stored.appLanguage, AppLanguage.system);
      expect(stored.pageSwitchAnimationEnabled, isTrue);
      expect(stored.previewOverlayOpacity, kDefaultPreviewOverlayOpacity);
      expect(stored.previewToolbarOpacity, kDefaultPreviewOverlayOpacity);
      expect(stored.previewFilmstripOpacity, kDefaultPreviewOverlayOpacity);
      expect(stored.previewFilmstripHeight, kPreviewFilmstripHeight);
      expect(stored.showPreviewFilmstrip, isTrue);
      expect(stored.showPreviewOverview, isTrue);
      expect(stored.mediaSortOrder, defaultMediaSortOrder);
    });

    test('round-trips additional settings and preview display controls',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();

      await repo.saveUseHalfSizeRawDecode(false);
      await repo.saveMaxCacheSize(1024);
      await repo.saveTimeDisplaySource(TimeDisplaySource.modifiedAt);
      await repo.saveAppLanguage(AppLanguage.english);
      await repo.saveShowPreviewFilmstrip(false);
      await repo.saveShowPreviewOverview(false);
      await repo.saveMediaSortOrder(MediaSortOrder.capturedNewest);

      final stored = await repo.loadViewPreferences();
      expect(stored.useHalfSizeRawDecode, isFalse);
      expect(stored.maxCacheSize, 1024);
      expect(stored.timeDisplaySource, TimeDisplaySource.modifiedAt);
      expect(stored.appLanguage, AppLanguage.english);
      expect(stored.showPreviewFilmstrip, isFalse);
      expect(stored.showPreviewOverview, isFalse);
      expect(stored.mediaSortOrder, MediaSortOrder.capturedNewest);
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

    test('persists each preview opacity independently', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.savePreviewOverlayOpacity(0.5);
      await repo.savePreviewToolbarOpacity(0.3);
      await repo.savePreviewFilmstripOpacity(0.8);
      var stored = await repo.loadViewPreferences();
      expect(stored.previewOverlayOpacity, 0.5);
      expect(stored.previewToolbarOpacity, 0.3);
      expect(stored.previewFilmstripOpacity, 0.8);

      await repo.savePreviewToolbarOpacity(0.9);
      stored = await repo.loadViewPreferences();
      expect(stored.previewOverlayOpacity, 0.5);
      expect(stored.previewToolbarOpacity, 0.9);
      expect(stored.previewFilmstripOpacity, 0.8);
    });

    test('round-trips filmstrip height across unrelated setting changes',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.savePreviewFilmstripHeight(187.5);
      final stored = await repo.loadViewPreferences();
      final settings = const ViewerSettings()
          .copyWith(previewFilmstripHeight: stored.previewFilmstripHeight)
          .copyWith(previewToolbarOpacity: 0.7);
      await repo.savePreviewToolbarOpacity(settings.previewToolbarOpacity);
      expect(settings.previewFilmstripHeight, 187.5);
      expect((await repo.loadViewPreferences()).previewFilmstripHeight, 187.5);
    });

    test('normalizes invalid stored filmstrip heights', () async {
      for (final (height, expected) in [
        (1.0, kMinPreviewFilmstripHeight),
        (500.0, kMaxPreviewFilmstripHeight),
        (double.nan, kPreviewFilmstripHeight),
        (double.infinity, kPreviewFilmstripHeight),
      ]) {
        SharedPreferences.setMockInitialValues({
          'preview_filmstrip_height': height,
        });
        final stored =
            await const PreferencesRepository().loadViewPreferences();
        expect(stored.previewFilmstripHeight, expected);
      }
    });

    test('migrates the shared opacity to each bar only once', () async {
      SharedPreferences.setMockInitialValues({'preview_overlay_opacity': 0.65});
      final repo = const PreferencesRepository();
      var stored = await repo.loadViewPreferences();
      expect(stored.previewToolbarOpacity, 0.65);
      expect(stored.previewFilmstripOpacity, 0.65);

      await repo.savePreviewOverlayOpacity(0.9);
      stored = await repo.loadViewPreferences();
      expect(stored.previewOverlayOpacity, 0.9);
      expect(stored.previewToolbarOpacity, 0.65);
      expect(stored.previewFilmstripOpacity, 0.65);
    });

    test('preserves a configured bar when migrating the other', () async {
      SharedPreferences.setMockInitialValues({
        'preview_overlay_opacity': 0.65,
        'preview_toolbar_opacity': 0.3,
      });
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.previewToolbarOpacity, 0.3);
      expect(stored.previewFilmstripOpacity, 0.65);
    });

    test('clamps each stored bar opacity to the slider range', () async {
      SharedPreferences.setMockInitialValues({
        'preview_toolbar_opacity': 0.0,
        'preview_filmstrip_opacity': 2.0,
      });
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.previewToolbarOpacity, kMinPreviewOverlayOpacity);
      expect(stored.previewFilmstripOpacity, kMaxPreviewOverlayOpacity);
    });

    test('round-trips the RAW view mode', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      await repo.saveRawViewMode(RawViewMode.embeddedJpeg);
      final stored = await repo.loadViewPreferences();
      expect(stored.rawViewMode, RawViewMode.embeddedJpeg);
    });

    test('leaves the RAW view mode null when nothing is stored', () async {
      // Null means "never chosen", so the caller keeps the ViewerSettings
      // default rather than being forced onto a mode.
      SharedPreferences.setMockInitialValues({});
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.rawViewMode, isNull);
    });

    test('ignores an unrecognised stored RAW view mode', () async {
      // A key written by a newer build must not crash an older one.
      SharedPreferences.setMockInitialValues({'raw_view_mode': 'fastPreview'});
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.rawViewMode, isNull);
    });

    test('migrates legacy auto-transparency-disabled key on first load',
        () async {
      SharedPreferences.setMockInitialValues({
        'preview_overlay_auto_transparency_enabled': false,
      });
      final stored = await const PreferencesRepository().loadViewPreferences();
      expect(stored.previewOverlayOpacity, kMaxPreviewOverlayOpacity);
      expect(stored.previewToolbarOpacity, kMaxPreviewOverlayOpacity);
      expect(stored.previewFilmstripOpacity, kMaxPreviewOverlayOpacity);
    });
  });

  group('PreferencesRepository loadWindowGeometry', () {
    test('returns defaults when nothing is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final geometry = await const PreferencesRepository().loadWindowGeometry();
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

  group('PreferencesRepository recent open items', () {
    test('round-trips recent files and folders', () async {
      SharedPreferences.setMockInitialValues({});
      final repo = const PreferencesRepository();
      const items = [
        RecentOpenItem(path: '/photos', isDirectory: true),
        RecentOpenItem(path: '/photos/IMG_0001.ARW', isDirectory: false),
      ];

      await repo.saveRecentOpenItems(items);

      expect(await repo.loadRecentOpenItems(), hasLength(2));
      final restored = await repo.loadRecentOpenItems();
      expect(restored[0].path, '/photos');
      expect(restored[0].isDirectory, isTrue);
      expect(restored[1].path, '/photos/IMG_0001.ARW');
      expect(restored[1].isDirectory, isFalse);
    });

    test('ignores corrupt recent-open entries', () async {
      SharedPreferences.setMockInitialValues({
        'recent_open_items': ['not json', '{"path":"/photos"}'],
      });

      expect(
          await const PreferencesRepository().loadRecentOpenItems(), isEmpty);
    });
  });
}
