import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/justified_grid_layout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/app.dart';
import 'package:rawviewer/core/decode_target.dart';
import 'package:rawviewer/core/preview_filmstrip_size.dart';
import 'package:rawviewer/core/media_types.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/raw_view_mode.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/preview/single_image_preview.dart';
import 'package:rawviewer/preview/widgets/preview_filmstrip.dart';
import 'package:rawviewer/ui/fast_page_scroll_physics.dart';
import 'package:rawviewer/media_filter.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/native_lib.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/ui/app_theme.dart';
import 'package:rawviewer/viewer_image.dart';

/// The scrolling content list for one settings category.
///
/// Needed because the narrow layout also mounts a horizontally scrolling tab
/// bar, so `find.byType(Scrollable).first` would scroll the wrong thing.
Finder settingsCategoryList(SettingsCategory category) {
  return find
      .byKey(PageStorageKey<String>('settings-category-${category.name}'));
}

/// Opens one settings category.
///
/// The page shows a rail on wide viewports and a scrollable tab bar on narrow
/// ones, so both keys are tried; only one is mounted at a time.
Future<void> openSettingsCategory(
  WidgetTester tester,
  SettingsCategory category,
) async {
  final tile = find.byKey(ValueKey('settings-category-tile-${category.name}'));
  final tab = find.byKey(ValueKey('settings-category-tab-${category.name}'));
  final target = tester.any(tile) ? tile : tab;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('bucketDecodeWidth', () {
    test('snaps up to the next bucket', () {
      expect(bucketDecodeWidth(1), kDecodeWidthBucket);
      expect(
          bucketDecodeWidth(kDecodeWidthBucket.toDouble()), kDecodeWidthBucket);
      expect(bucketDecodeWidth(kDecodeWidthBucket + 1), kDecodeWidthBucket * 2);
      expect(bucketDecodeWidth(300), 384);
    });

    test('is stable across small width changes', () {
      // The point of bucketing: resizing the window by a pixel must not change
      // the decode target, otherwise every cached image is invalidated.
      final widths = [400.0, 401.0, 447.0, 512.0];
      final buckets = widths.map(bucketDecodeWidth).toSet();
      expect(buckets, hasLength(1));
      expect(buckets.single, 512);
    });
  });

  group('image preview motion', () {
    test('uses a clear JPEG export name for RAW files', () {
      expect(
        embeddedJpegExportFileName('/photos/IMG_0001.ARW'),
        'IMG_0001-embedded.jpg',
      );
    });

    test('shows a bounded neighborhood around the active page', () {
      expect(
        previewNavigationIndices(currentIndex: 3, itemCount: 8),
        [1, 2, 3, 4, 5],
      );
      expect(
        previewNavigationIndices(currentIndex: 0, itemCount: 2),
        [0, 1],
      );
      expect(
        previewNavigationIndices(currentIndex: 10, itemCount: 0),
        isEmpty,
      );
    });

    test('maps the zoomed viewport onto the overview map', () {
      final transform = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2)
        ..setTranslationRaw(-100, -50, 0);

      final rect = previewOverviewViewportRect(
        transform: transform,
        viewportSize: const Size(1000, 800),
        mapSize: const Size(200, 160),
      );
      expect(rect.left, closeTo(10, 0.001));
      expect(rect.top, closeTo(5, 0.001));
      expect(rect.right, closeTo(110, 0.001));
      expect(rect.bottom, closeTo(85, 0.001));
    });

    test('wraps clockwise and counterclockwise quarter turns', () {
      expect(rotateImageQuarterTurns(0, 1), 1);
      expect(rotateImageQuarterTurns(3, 1), 0);
      expect(rotateImageQuarterTurns(0, -1), 3);
      expect(rotateImageQuarterTurns(1, -1), 0);
    });

    test('enforces zoom bounds and separates zoom-out at fit scale', () {
      expect(clampPreviewScale(0.1), kMinPreviewScale);
      expect(clampPreviewScale(1.5), 1.5);
      expect(clampPreviewScale(10), kMaxPreviewScale);

      expect(
        shouldResetPreviewPositionAtFitScale(
          currentScale: 1.25,
          targetScale: 0.9,
        ),
        isTrue,
      );
      expect(
        shouldResetPreviewPositionAtFitScale(
          currentScale: 1,
          targetScale: 0.8,
        ),
        isFalse,
      );
      expect(
        shouldResetPreviewPositionAtFitScale(
          currentScale: 0.8,
          targetScale: 1.1,
        ),
        isTrue,
      );
    });

    testWidgets('double tap resets zoom and pan without rotating',
        (tester) async {
      final scrolling = ValueNotifier<bool>(false);
      addTearDown(scrolling.dispose);
      final imageStore = ImageStore(LruCache<String, ViewerImage>(1024));

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: SizedBox(
            width: 400,
            height: 300,
            child: SingleImagePreview(
              mediaGroup: const MediaGroup(
                primary: MediaFile(
                  path: '/missing-test-image.jpg',
                  kind: MediaKind.bitmap,
                ),
              ),
              thumbnailResizeWidth: 256,
              previewThumbnailResizeWidth: 512,
              imageStore: imageStore,
              settings: const ViewerSettings(),
              rotationQuarterTurns: 1,
              viewMode: RawViewMode.decodedRaw,
              onResetRotationRequested: () {},
              onSwitchRequest: (_) {},
              onTrackpadPanStart: (_) {},
              onTrackpadPanUpdate: (_) {},
              onTrackpadPanEnd: (_) {},
              onTrackpadPanCancel: () {},
              isActive: true,
              showPreviewOverview: false,
              overviewBottomInset: 0,
              isFastScrolling: scrolling,
            ),
          ),
        ),
      );
      await tester.pump();

      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = viewer.transformationController!;
      controller.value = Matrix4.identity()
        ..translateByDouble(-40, -25, 0, 1)
        ..scaleByDouble(2, 2, 2, 1);
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(2, 0.001));

      const tapPosition = Offset(200, 150);
      await tester.tapAt(tapPosition);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(tapPosition);
      await tester.pump(const Duration(milliseconds: 350));

      expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
      final translation = controller.value.getTranslation();
      expect(translation.x, closeTo(0, 0.001));
      expect(translation.y, closeTo(0, 0.001));
    });

    testWidgets('display controls stay fixed while switching images',
        (tester) async {
      final groups = [
        const MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image-1.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
        const MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image-2.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImagePreviewPage(
            mediaGroups: groups,
            initialIndex: 0,
            thumbnailResizeWidth: 256,
            imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
            timestampRepository: TimestampRepository(),
            initialSettings: const ViewerSettings(),
            onClose: () {},
            onRawViewModeChanged: (_) {},
            onPreviewFilmstripHeightChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final zoomIn = find.byIcon(Icons.zoom_in);
      final initialPosition = tester.getTopLeft(zoomIn);
      final controller = tester
          .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
          .transformationController!;
      controller.value = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
      await tester.pump();

      await tester.tap(zoomIn);
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));

      await tester.tap(zoomIn);
      await tester.pump(const Duration(milliseconds: 1));
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3.125, 0.001));
      await tester.pump(const Duration(milliseconds: 400));
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3.125, 0.001));

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.byIcon(Icons.zoom_in), findsOneWidget);
      expect(tester.getTopLeft(zoomIn), initialPosition);
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(zoomIn), initialPosition);
    });

    testWidgets('single-file preview can load its directory on demand',
        (tester) async {
      final groups = [
        const MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
      ];
      var loadCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImagePreviewPage(
            mediaGroups: groups,
            initialIndex: 0,
            thumbnailResizeWidth: 256,
            imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
            timestampRepository: TimestampRepository(),
            initialSettings: const ViewerSettings(),
            onLoadDirectory: () async {
              loadCount++;
              return [
                ...groups,
                const MediaGroup(
                  primary: MediaFile(
                    path: '/missing-test-image-2.jpg',
                    kind: MediaKind.bitmap,
                  ),
                ),
              ];
            },
            onClose: () {},
            onRawViewModeChanged: (_) {},
            onPreviewFilmstripHeightChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final loadButton = find.byTooltip('Load images from this directory');
      expect(loadButton, findsOneWidget);
      expect(find.text('Load directory'), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-directory-load-panel')),
          findsOneWidget);
      expect(find.byType(PreviewFilmstrip), findsNothing);
      await tester.tap(loadButton);
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      expect(find.byTooltip('Load images from this directory'), findsNothing);
      expect(find.byKey(const ValueKey('preview-directory-load-panel')),
          findsNothing);
      expect(find.byType(PreviewFilmstrip), findsOneWidget);
    });

    testWidgets(
        'single-file preview keeps directory loading available on cancel',
        (tester) async {
      const groups = [
        MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
      ];
      var loadCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImagePreviewPage(
            mediaGroups: groups,
            initialIndex: 0,
            thumbnailResizeWidth: 256,
            imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
            timestampRepository: TimestampRepository(),
            initialSettings: const ViewerSettings(),
            onLoadDirectory: () async {
              loadCount++;
              return null;
            },
            onClose: () {},
            onRawViewModeChanged: (_) {},
            onPreviewFilmstripHeightChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Load images from this directory'));
      await tester.pumpAndSettle();

      expect(loadCount, 1);
      expect(find.byKey(const ValueKey('preview-directory-load-panel')),
          findsOneWidget);
      expect(find.byType(PreviewFilmstrip), findsNothing);
      expect(find.byTooltip('Load images from this directory'), findsOneWidget);
      expect(find.text('Load directory'), findsOneWidget);
    });

    test('keeps preview opening and discrete navigation responsive', () {
      expect(
        kImagePreviewOpenTransitionDuration,
        const Duration(milliseconds: 100),
      );
      expect(
        kImagePreviewCloseTransitionDuration,
        const Duration(milliseconds: 80),
      );
      expect(kImagePreviewToolbarHeight, 52);
      expect(
        kImagePreviewPageSwitchDuration,
        const Duration(milliseconds: 55),
      );
      expect(
        kImagePreviewRapidSwitchThreshold,
        const Duration(milliseconds: 180),
      );
      expect(
        kImagePreviewRapidSwitchSettleDelay,
        const Duration(milliseconds: 140),
      );
    });

    test('clamps the resizable filmstrip and scales its thumbnails', () {
      expect(
        clampPreviewFilmstripHeight(
          height: 400,
          viewportHeight: 600,
          topInset: 0,
          bottomInset: 0,
        ),
        kMaxPreviewFilmstripHeight,
      );
      expect(
        clampPreviewFilmstripHeight(
          height: 1,
          viewportHeight: 600,
          topInset: 0,
          bottomInset: 0,
        ),
        kMinPreviewFilmstripHeight,
      );
      expect(
        previewFilmstripThumbnailSize(kPreviewFilmstripHeight),
        const Size(kPreviewFilmstripItemWidth, kPreviewFilmstripItemHeight),
      );
    });

    testWidgets('resizes the bottom filmstrip from its top boundary',
        (tester) async {
      final groups = [
        const MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImagePreviewPage(
            mediaGroups: groups,
            initialIndex: 0,
            thumbnailResizeWidth: 256,
            imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
            timestampRepository: TimestampRepository(),
            initialSettings: const ViewerSettings(),
            onClose: () {},
            onRawViewModeChanged: (_) {},
            onPreviewFilmstripHeightChanged: (_) {},
          ),
        ),
      );
      await tester.pump();

      final handle = find.byKey(
        const ValueKey('preview-filmstrip-resize-handle'),
      );
      expect(handle, findsOneWidget);
      final cursor = tester.widget<MouseRegion>(
        find.ancestor(of: handle, matching: find.byType(MouseRegion)).first,
      );
      expect(cursor.cursor, SystemMouseCursors.resizeUpDown);
      final filmstripPanel = find.byKey(
        const ValueKey('preview-filmstrip-panel'),
      );
      final handleRect = tester.getRect(handle);
      final filmstripRect = tester.getRect(filmstripPanel);
      expect(
        handleRect.top,
        filmstripRect.top - previewFilmstripResizeHandleAboveBar,
      );
      expect(
        handleRect.bottom,
        filmstripRect.top +
            previewFilmstripResizeHandleHeight -
            previewFilmstripResizeHandleAboveBar,
      );

      await tester.drag(handle, const Offset(0, -100));
      await tester.pump();
      expect(
        tester.widget<PreviewFilmstrip>(find.byType(PreviewFilmstrip)).height,
        kPreviewFilmstripHeight + 100,
      );

      await tester.drag(handle, const Offset(0, 500));
      await tester.pump();
      expect(
        tester.widget<PreviewFilmstrip>(find.byType(PreviewFilmstrip)).height,
        kMinPreviewFilmstripHeight,
      );
    });

    test('settles swipe navigation with a stiff critically damped spring', () {
      final spring = const FastPageScrollPhysics().spring;

      expect(spring.mass, 0.7);
      expect(spring.stiffness, 1600.0);
      expect(spring.damping, closeTo(66.93, 0.01));
    });
  });

  group('desktop popup menu styling', () {
    test('uses the compact Raw Viewer menu motion and theme', () {
      expect(
        rawViewerPopupMenuAnimationStyle.duration,
        const Duration(milliseconds: 100),
      );
      expect(
        rawViewerPopupMenuAnimationStyle.reverseDuration,
        const Duration(milliseconds: 70),
      );
      expect(rawViewerTheme.useMaterial3, isFalse);
      expect(
        rawViewerTheme.popupMenuTheme.color,
        RawViewerColors.raisedSurface,
      );
      expect(
        rawViewerTheme.popupMenuTheme.surfaceTintColor,
        Colors.transparent,
      );
    });

    test('uses a neutral gray image preview background', () {
      expect(RawViewerColors.previewBackground, const Color(0xFF4A4A4A));
    });
  });

  group('ViewerSettings', () {
    test('defaults the grid to 3:2', () {
      const settings = ViewerSettings();

      expect(settings.gridAspectRatio, GridAspectRatio.ratio3x2);
      expect(settings.gridAspectRatio.aspectRatio, 3 / 2);
    });

    test('copyWith changes only the requested grid ratio', () {
      const original = ViewerSettings(maxCacheSize: 1024);
      final updated = original.copyWith(
        gridAspectRatio: GridAspectRatio.ratio16x9,
      );

      expect(updated.gridAspectRatio, GridAspectRatio.ratio16x9);
      expect(updated.maxCacheSize, original.maxCacheSize);
    });

    test('defaults page switch animation to enabled and can disable it', () {
      const original = ViewerSettings();
      final updated = original.copyWith(pageSwitchAnimationEnabled: false);

      expect(original.pageSwitchAnimationEnabled, isTrue);
      expect(updated.pageSwitchAnimationEnabled, isFalse);
      expect(updated.gridAspectRatio, original.gridAspectRatio);
    });

    test('defaults preview overlay opacity and can customize it', () {
      const original = ViewerSettings();
      final updated = original.copyWith(
        previewOverlayOpacity: 0.65,
      );

      expect(original.previewOverlayOpacity, kDefaultPreviewOverlayOpacity);
      expect(updated.previewOverlayOpacity, 0.65);
      expect(updated.previewToolbarOpacity, kDefaultPreviewOverlayOpacity);
      expect(updated.previewFilmstripOpacity, kDefaultPreviewOverlayOpacity);
      final separateBars = updated
          .copyWith(previewToolbarOpacity: 0.3, previewFilmstripOpacity: 0.8)
          .copyWith(maxCacheSize: 1024);
      expect(separateBars.previewOverlayOpacity, 0.65);
      expect(separateBars.previewToolbarOpacity, 0.3);
      expect(separateBars.previewFilmstripOpacity, 0.8);
      expect(
        updated.pageSwitchAnimationEnabled,
        original.pageSwitchAnimationEnabled,
      );
    });

    for (final locale in [const Locale('en'), const Locale('zh')]) {
      testWidgets('preview opacity controls fit a narrow window in $locale',
          (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsPage(
            settings: const ViewerSettings(
              previewToolbarOpacity: 0.3,
              previewFilmstripOpacity: 0.6,
              previewOverlayOpacity: 0.5,
            ),
            onClose: () {},
            onSettingsChanged: (_) {},
          ),
        ));
        await tester.pumpAndSettle();
        // 360px is below the rail breakpoint, so the categories render as a
        // scrollable tab bar; the opacity sliders live under Appearance.
        await openSettingsCategory(tester, SettingsCategory.appearance);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(SettingsPage)),
        )!;
        for (final (key, title, value) in [
          ('preview-toolbar-opacity', l10n.previewToolbarOpacityTitle, 0.3),
          ('preview-filmstrip-opacity', l10n.previewFilmstripOpacityTitle, 0.6),
          ('preview-overlay-opacity', l10n.previewOverlayOpacityTitle, 0.5),
        ]) {
          final row = find.byKey(ValueKey(key));
          await tester.scrollUntilVisible(
            row,
            200,
            scrollable: find.descendant(
              of: settingsCategoryList(SettingsCategory.appearance),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.pumpAndSettle();
          final slider =
              find.descendant(of: row, matching: find.byType(Slider));
          expect(tester.widget<Slider>(slider).value, value);
          final sliderRect = tester.getRect(slider);
          final titleRect = tester.getRect(find.text(title));
          expect(titleRect.left, greaterThanOrEqualTo(0));
          expect(titleRect.right, lessThanOrEqualTo(sliderRect.left));
          expect(sliderRect.right, lessThanOrEqualTo(360));
          expect(tester.takeException(), isNull);
        }
      });
    }

    test('supports adaptive grid sizing', () {
      const settings = ViewerSettings(
        gridAspectRatio: GridAspectRatio.adaptive,
      );

      expect(settings.gridAspectRatio.isAdaptive, isTrue);
      expect(settings.gridAspectRatio.aspectRatio, 3 / 2);
    });

    testWidgets('publishes each setting change immediately', (tester) async {
      ViewerSettings? updatedSettings;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: SettingsPage(
            settings: const ViewerSettings(),
            onClose: () {},
            onSettingsChanged: (settings) {
              updatedSettings = settings;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Grid ratio, page-switch animation and the opacity sliders all live
      // under Appearance, so one category switch covers this whole test.
      await openSettingsCategory(tester, SettingsCategory.appearance);
      final settingsList = find.descendant(
        of: settingsCategoryList(SettingsCategory.appearance),
        matching: find.byType(Scrollable),
      );
      final wideGrid = find.byKey(const ValueKey('grid-aspect-ratio16x9'));
      await tester.scrollUntilVisible(
        wideGrid,
        300,
        scrollable: settingsList,
      );
      await tester.pumpAndSettle();
      await tester.tap(wideGrid);
      await tester.pump();
      expect(updatedSettings!.gridAspectRatio, GridAspectRatio.ratio16x9);

      final adaptiveGrid = find.byKey(const ValueKey('grid-aspect-adaptive'));
      await tester.ensureVisible(adaptiveGrid);
      await tester.pumpAndSettle();
      await tester.tap(adaptiveGrid);
      await tester.pump();
      expect(updatedSettings!.gridAspectRatio, GridAspectRatio.adaptive);

      // The RAW view mode is chosen from the preview's own switch and
      // persisted; it is deliberately absent from this page.
      expect(find.byKey(const ValueKey('raw-preview-decoded')), findsNothing);

      final pageSwitchAnimation =
          find.byKey(const ValueKey('page-switch-animation'));
      await tester.scrollUntilVisible(
        pageSwitchAnimation,
        -300,
        scrollable: settingsList,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: pageSwitchAnimation,
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(updatedSettings!.pageSwitchAnimationEnabled, isFalse);

      final previewOverlayOpacity =
          find.byKey(const ValueKey('preview-overlay-opacity'));
      await tester.scrollUntilVisible(
        previewOverlayOpacity,
        300,
        scrollable: settingsList,
      );
      await tester.pumpAndSettle();
      final previewOverlaySlider = find.descendant(
        of: previewOverlayOpacity,
        matching: find.byType(Slider),
      );
      await tester
          .tapAt(tester.getCenter(previewOverlaySlider) + const Offset(50, 0));
      await tester.pump();
      expect(updatedSettings!.previewOverlayOpacity, greaterThan(0.42));
      final toolsOpacity = updatedSettings!.previewOverlayOpacity;
      expect(updatedSettings!.previewToolbarOpacity,
          kDefaultPreviewOverlayOpacity);
      expect(updatedSettings!.previewFilmstripOpacity,
          kDefaultPreviewOverlayOpacity);

      Future<void> adjustBarSlider(String key) async {
        final row = find.byKey(ValueKey(key));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        final slider = find.descendant(of: row, matching: find.byType(Slider));
        await tester.tapAt(tester.getCenter(slider) + const Offset(30, 0));
        await tester.pump();
      }

      await adjustBarSlider('preview-toolbar-opacity');
      final toolbarOpacity = updatedSettings!.previewToolbarOpacity;
      expect(toolbarOpacity, greaterThan(kDefaultPreviewOverlayOpacity));
      expect(updatedSettings!.previewFilmstripOpacity,
          kDefaultPreviewOverlayOpacity);
      expect(updatedSettings!.previewOverlayOpacity, toolsOpacity);

      await adjustBarSlider('preview-filmstrip-opacity');
      expect(updatedSettings!.previewFilmstripOpacity,
          greaterThan(kDefaultPreviewOverlayOpacity));
      expect(updatedSettings!.previewToolbarOpacity, toolbarOpacity);
      expect(updatedSettings!.previewOverlayOpacity, toolsOpacity);
    });

    testWidgets('updates file associations through bulk actions',
        (tester) async {
      final appliedExtensions = <Set<String>>[];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: SettingsPage(
            settings: ViewerSettings(
              fileAssociations: FileAssociationSettings(
                supported: true,
                bindings: {
                  for (final extension in supportedExtensions) extension: false,
                },
              ),
            ),
            onClose: () {},
            onSettingsChanged: (_) {},
            onFileAssociationsChanged: (extensions) async {
              appliedExtensions.add(Set<String>.of(extensions));
              return FileAssociationSettings(
                supported: true,
                bindings: {
                  for (final extension in supportedExtensions)
                    extension: extensions.contains(extension),
                },
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await openSettingsCategory(tester, SettingsCategory.integration);
      final settingsList = find.descendant(
        of: settingsCategoryList(SettingsCategory.integration),
        matching: find.byType(Scrollable),
      );
      final actions = find.byKey(const ValueKey('file-association-actions'));
      await tester.scrollUntilVisible(actions, 300, scrollable: settingsList);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('file-association-enable-all')),
      );
      await tester.pumpAndSettle();
      expect(appliedExtensions.last, unorderedEquals(supportedExtensions));

      await tester.tap(
        find.byKey(const ValueKey('file-association-enable-raw')),
      );
      await tester.pumpAndSettle();
      expect(appliedExtensions.last, unorderedEquals(rawExtensions));

      await tester.tap(
        find.byKey(const ValueKey('file-association-disable-all')),
      );
      await tester.pumpAndSettle();
      expect(appliedExtensions.last, isEmpty);
    });
  });

  group('buildJustifiedGridRows', () {
    test('fills every row while retaining each image proportion', () {
      final rows = buildJustifiedGridRows(
        aspectRatios: const [1, 2, 1, 1.5, 0.75],
        availableWidth: 600,
        targetRowHeight: 200,
      );

      expect(rows, isNotEmpty);
      expect(rows.map((row) => row.indices).expand((indices) => indices),
          orderedEquals([0, 1, 2, 3, 4]));
      for (final row in rows) {
        expect(row.widths.reduce((sum, width) => sum + width),
            closeTo(600, 0.001));
        for (var index = 0; index < row.indices.length; index++) {
          final ratio = [1, 2, 1, 1.5, 0.75][row.indices[index]];
          expect(row.widths[index] / row.height, closeTo(ratio, 0.001));
        }
      }
    });

    test('caps an oversized final row while retaining the image ratio', () {
      final rows = buildJustifiedGridRows(
        aspectRatios: const [1, 1, 1, 1],
        availableWidth: 400,
        targetRowHeight: 150,
        maxFinalRowHeight: 200,
      );

      expect(rows.last.height, 200);
      expect(rows.last.widths, [200]);
      expect(rows.last.widths.single / rows.last.height, 1);
      expect(rows.expand((row) => row.indices), orderedEquals([0, 1, 2, 3]));
    });

    test('still justifies a normal-sized final row', () {
      final rows = buildJustifiedGridRows(
        aspectRatios: const [1, 1, 1, 2],
        availableWidth: 400,
        targetRowHeight: 150,
        maxFinalRowHeight: 300,
      );

      expect(rows.last.widths.reduce((sum, width) => sum + width),
          closeTo(400, 0.001));
    });
  });

  group('LruCache', () {
    test('evicts least-recently-used entries and reports them', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        3,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 1);
      cache.put('c', 1);
      cache.get('a'); // 'a' becomes most recently used, so 'b' is next out.
      cache.put('d', 1);

      expect(evicted, ['b']);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.length, 3);
    });

    test('reports replaced values so their handles can be released', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        10,
        onEvict: (_, value) => evicted.add(value),
      );

      cache.put('a', 1);
      cache.put('a', 2);

      expect(evicted, [1]);
      expect(cache.get('a'), 2);
      expect(cache.length, 1);
    });

    test('rejects an oversized value instead of emptying the cache', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        100,
        sizeOf: (value) => value,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('small', 40);
      cache.put('huge', 500);

      // The oversized entry is handed straight back for disposal, and the
      // entries that do fit survive.
      expect(evicted, ['huge']);
      expect(cache.containsKey('small'), isTrue);
      expect(cache.containsKey('huge'), isFalse);
      expect(cache.size, 40);
    });

    test('accounts for size and evicts until within budget', () {
      final cache = LruCache<String, int>(100, sizeOf: (value) => value);

      cache.put('a', 60);
      cache.put('b', 60);

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.size, 60);
    });

    test('clear reports every entry', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        10,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 1);
      cache.clear();

      expect(evicted, unorderedEquals(['a', 'b']));
      expect(cache.length, 0);
      expect(cache.size, 0);
    });
  });

  group('ImageStore.cacheKey', () {
    const path = '/photos/a.arw';

    test('separates layers and half-size variants', () {
      final thumbnail = ImageStore.cacheKey(path, RawLayer.thumbnail);
      final embedded = ImageStore.cacheKey(path, RawLayer.embeddedJpeg);
      final half = ImageStore.cacheKey(path, RawLayer.decoded, halfSize: 1);
      final full = ImageStore.cacheKey(path, RawLayer.decoded, halfSize: 0);

      expect({thumbnail, embedded, half, full}, hasLength(4));
    });

    test('separates the thumbnail layer from the embedded JPEG', () {
      // The thumbnail layer falls back to a RAW decode, so it may hold pixels
      // that are not the embedded JPEG at all. Sharing one entry would let a
      // fallback image answer a request for the real embedded JPEG.
      expect(
        ImageStore.cacheKey(path, RawLayer.thumbnail, targetWidth: 512),
        isNot(
            ImageStore.cacheKey(path, RawLayer.embeddedJpeg, targetWidth: 512)),
      );
    });

    test('separates resolutions of the same layer', () {
      // The grid and the full-screen preview want the same source at different
      // sizes; sharing one entry would show a blurry preview.
      final thumb =
          ImageStore.cacheKey(path, RawLayer.thumbnail, targetWidth: 512);
      final fullRes = ImageStore.cacheKey(path, RawLayer.thumbnail);

      expect(thumb, isNot(fullRes));
    });

    test('is stable for identical requests', () {
      expect(
        ImageStore.cacheKey(path, RawLayer.thumbnail, targetWidth: 512),
        ImageStore.cacheKey(path, RawLayer.thumbnail, targetWidth: 512),
      );
    });
  });

  group('decodeToUiImage', () {
    // A 2x2 RGBA block: red, green, blue, white.
    LibRawImage rgbaFixture() {
      final pixels = Uint8List.fromList(<int>[
        255, 0, 0, 255, /**/ 0, 255, 0, 255, //
        0, 0, 255, 255, /**/ 255, 255, 255, 255, //
      ]);
      return LibRawImage(pixels, 2, 2, RawPixelFormat.rgba8888, 2 * 4);
    }

    test('wraps raw RGBA pixels without re-encoding', () async {
      final image = await decodeToUiImage(rgbaFixture());
      addTearDown(image.dispose);

      expect(image.width, 2);
      expect(image.height, 2);
    });

    test('preserves pixel values', () async {
      final image = await decodeToUiImage(rgbaFixture());
      addTearDown(image.dispose);

      final data = await image.toByteData();
      expect(data, isNotNull);
      // First pixel stays opaque red, confirming channel order survives.
      expect(data!.buffer.asUint8List().sublist(0, 4), [255, 0, 0, 255]);
    });

    test('downscales to targetWidth', () async {
      final pixels = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 255);
      final source = LibRawImage(pixels, 8, 8, RawPixelFormat.rgba8888, 8 * 4);

      final image = await decodeToUiImage(source, targetWidth: 4);
      addTearDown(image.dispose);

      expect(image.width, 4);
      expect(image.height, 4);
    });

    test('never upscales past the source resolution', () async {
      final image = await decodeToUiImage(rgbaFixture(), targetWidth: 64);
      addTearDown(image.dispose);

      // Upscaling a preview costs memory and adds no detail.
      expect(image.width, 2);
      expect(image.height, 2);
    });
  });

  group('ViewerImage', () {
    test('clone shares pixels and survives the original being disposed',
        () async {
      final pixels = Uint8List.fromList(<int>[1, 2, 3, 255]);
      final uiImage = await decodeToUiImage(
        LibRawImage(pixels, 1, 1, RawPixelFormat.rgba8888, 4),
      );

      final master = ViewerImage(image: uiImage);
      final handle = master.clone();

      master.dispose();

      // The clone is an independent handle onto the same underlying image, so
      // a widget disposing its copy must not invalidate the cached master.
      expect(handle.width, 1);
      expect(handle.image.debugDisposed, isFalse);

      handle.dispose();
    });

    test('reports its texture footprint for cache accounting', () async {
      final pixels = Uint8List(4 * 4 * 4);
      final uiImage = await decodeToUiImage(
        LibRawImage(pixels, 4, 4, RawPixelFormat.rgba8888, 4 * 4),
      );
      final image = ViewerImage(image: uiImage);
      addTearDown(image.dispose);

      expect(image.sizeInBytes, 4 * 4 * 4);
    });
  });

  testWidgets('home toolbar fits a narrow viewport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MediaFilterButton), findsOneWidget);
  });

  testWidgets('home puts thumbnail controls in the lower-right corner',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);

    final zoomInPosition = tester.getTopLeft(find.byIcon(Icons.zoom_in));
    final zoomOutPosition = tester.getTopLeft(find.byIcon(Icons.zoom_out));
    expect(zoomInPosition.dx, greaterThan(600));
    expect(zoomInPosition.dy, greaterThan(400));
    expect(zoomOutPosition.dx, greaterThan(600));
    expect(zoomOutPosition.dy, greaterThan(400));
  });

  testWidgets('gallery actions menu contains all folder actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    final actionsButton = find.byIcon(Icons.more_vert);
    expect(actionsButton, findsOneWidget);
    expect(tester.getTopLeft(actionsButton).dx, lessThan(60));
    expect(
      tester.getTopLeft(find.byIcon(Icons.folder_open_outlined)).dy,
      greaterThan(100),
    );
    expect(
      tester.getTopLeft(find.byIcon(Icons.file_open_outlined)).dy,
      greaterThan(100),
    );

    await tester.tap(actionsButton);
    await tester.pumpAndSettle();

    final popupMenuItems = find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem,
    );
    expect(popupMenuItems, findsNWidgets(4));
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('No recent files or folders'), findsNothing);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.file_open_outlined).last,
        matching: popupMenuItems,
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.folder_open_outlined).last,
        matching: popupMenuItems,
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.byIcon(Icons.open_in_new),
        matching: popupMenuItems,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem && !widget.enabled,
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.byKey(const ValueKey('recent-open-submenu')));
    await tester.pumpAndSettle();
    expect(find.text('No recent files or folders'), findsOneWidget);
  });

  testWidgets('home shows saved recent files and folders', (tester) async {
    SharedPreferences.setMockInitialValues({
      'recent_open_items': [
        '{"path":"/photos","isDirectory":true}',
        '{"path":"/photos/IMG_0001.ARW","isDirectory":false}',
      ],
    });
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('photos'), findsOneWidget);
    expect(find.text('/photos/IMG_0001.ARW'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('/photos/IMG_0001.ARW'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recent-open-submenu')));
    await tester.pumpAndSettle();
    expect(find.text('/photos/IMG_0001.ARW'), findsNWidgets(2));
  });
}
