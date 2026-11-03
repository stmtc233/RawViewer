import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/native_lib.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/preview/widgets/preview_chrome.dart';
import 'package:rawviewer/preview/widgets/preview_hover_reveal.dart';
import 'package:rawviewer/preview/widgets/preview_overview_map.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';
import 'package:rawviewer/worker_service.dart';

class _FixtureImageStore extends ImageStore {
  _FixtureImageStore(this.image)
      : super(LruCache<String, ViewerImage>(1,
            onEvict: (_, image) => image.dispose()));

  final ViewerImage image;

  @override
  ViewerImage? peek(String filePath, RawLayer layer,
          {int halfSize = 1, int? targetWidth}) =>
      image.clone();

  @override
  Future<ViewerImage?> load(String filePath, RawLayer layer,
          {int halfSize = 1,
          int? targetWidth,
          TaskPriority priority = TaskPriority.high,
          void Function(WorkerTask<LibRawImage?> task)? onTaskStarted,
          ImageLoadInterest? interest}) async =>
      image.clone();
}

/// The opacity the preview chrome currently gives [control].
double chromeOpacity(WidgetTester tester, Finder control) {
  final region = find
      .ancestor(of: control, matching: find.byType(PreviewChromeRegion))
      .first;
  if (!tester.widget<PreviewChromeRegion>(region).fades) return 1;
  return tester
      .widget<AnimatedOpacity>(find
          .descendant(of: region, matching: find.byType(AnimatedOpacity))
          .first)
      .opacity;
}

void main() {
  Future<ViewerImage> redImage(WidgetTester tester, Size size) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFF0000),
    );
    final picture = recorder.endRecording();
    final image = ViewerImage(
      image: (await tester.runAsync(
        () => picture.toImage(size.width.toInt(), size.height.toInt()),
      ))!,
    );
    picture.dispose();
    addTearDown(image.dispose);
    return image;
  }

  for (final size in [const Size(800, 600), const Size(360, 800)]) {
    testWidgets('image fills the window beneath the floating bar at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final image = await redImage(tester, size);
      final boundaryKey = GlobalKey();
      final safePadding = size.width < 400
          ? const EdgeInsets.only(top: 24, bottom: 20)
          : EdgeInsets.zero;

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(size: size, padding: safePadding),
          child: RepaintBoundary(
            key: boundaryKey,
            child: ImagePreviewPage(
              mediaGroups: const [
                MediaGroup(
                  primary: MediaFile(path: '/fixture.arw', kind: MediaKind.raw),
                ),
              ],
              initialIndex: 0,
              thumbnailResizeWidth: 256,
              imageStore: _FixtureImageStore(image),
              timestampRepository: TimestampRepository(),
              initialSettings: const ViewerSettings(),
              onClose: () {},
              onRawViewModeChanged: (_) {},
              onPreviewFilmstripHeightChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final toolbar = find.byKey(const ValueKey('preview-toolbar'));
      final filmstrip = find.byKey(const ValueKey('preview-filmstrip-panel'));

      /// Whether the red photo shows at [point] in the rendered page.
      Future<bool> photoVisibleAt(Offset point) async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        late bool visible;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage();
          try {
            final pixels = (await screenshot.toByteData())!;
            final offset =
                (point.dy.toInt() * screenshot.width + point.dx.toInt()) * 4;
            visible =
                pixels.getUint8(offset) - pixels.getUint8(offset + 1) > 80;
          } finally {
            screenshot.dispose();
          }
        });
        return visible;
      }

      // Just above the bottom of the bar, where the scrim has faded out.
      final underBar = Offset(
        size.width / 2,
        safePadding.top + kImagePreviewToolbarHeight - 4,
      );
      final underFilmstrip = Offset(2, size.height - 8);

      Future<void> zoomIn() async {
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byIcon(Icons.zoom_in));
          await tester.pumpAndSettle();
        }
      }

      void expectFittedViewport() {
        final fittedRect = tester.getRect(find.byType(InteractiveViewer));
        // The bar floats: the photo starts at the top of the safe area.
        expect(fittedRect.top, safePadding.top);
        // The filmstrip is docked: the photo stops above it.
        expect(fittedRect.bottom, tester.getTopLeft(filmstrip).dy);
      }

      expectFittedViewport();
      expect(tester.getRect(toolbar).top, 0);
      expect(await photoVisibleAt(underBar), isTrue);
      expect(await photoVisibleAt(underFilmstrip), isFalse);
      final initialViewport = tester.getRect(find.byType(PageView));
      expect(initialViewport, Offset.zero & size);

      await zoomIn();
      // A docked filmstrip is opaque: zooming never shows the photo through it.
      expect(await photoVisibleAt(underFilmstrip), isFalse);
      await tester.tap(find.byIcon(Icons.filter_center_focus));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey('preview-filmstrip-resize-handle')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageView)), initialViewport);
      expectFittedViewport();

      await zoomIn();
      final overviewRect = tester.getRect(find.byType(PreviewOverviewMap));
      final controlsRect = tester.getRect(find.byIcon(Icons.zoom_in));
      final filmstripRect = tester.getRect(filmstrip);
      expect(overviewRect.bottom, lessThan(controlsRect.top));
      expect(controlsRect.bottom, lessThan(filmstripRect.top));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ImagePreviewPage)),
      )!;
      await tester.tap(find.byTooltip(l10n.previewDisplayControlsTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.previewFilmstripTitle));
      await tester.pumpAndSettle();
      expect(filmstrip, findsNothing);
      expect(tester.getRect(find.byType(PageView)), initialViewport);
      expect(
        tester.getRect(find.byType(PreviewOverviewMap)).bottom,
        closeTo(
            size.height -
                safePadding.bottom -
                previewImageControlsHeight -
                previewOverviewGap -
                12,
            0.001),
      );
      await tester.tap(find.byTooltip(l10n.showExifTooltip));
      await tester.pump();
      final sidebar = find.byKey(const ValueKey('preview-exif-sidebar'));
      expect(sidebar, findsOneWidget);
      final sidebarRect = tester.getRect(sidebar);
      expect(sidebarRect.right, size.width);
      expect(sidebarRect.bottom, size.height);
      if (size.width >= 720) {
        // Docked beside the photo: the sidebar takes the full height and the
        // floating bar spans only the photo.
        expect(sidebarRect.top, safePadding.top);
        expect(tester.getRect(toolbar).right, sidebarRect.left);
        expect(tester.getRect(find.byType(PageView)).right, sidebarRect.left);
      } else {
        // Over the photo: below the bar, so the bar stays reachable.
        expect(sidebarRect.top, safePadding.top + kImagePreviewToolbarHeight);
        expect(tester.getRect(toolbar).right, size.width);
        expect(tester.getRect(find.byType(PageView)).right, size.width);
      }
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(sidebar, findsNothing);
      expect(tester.getRect(find.byType(PageView)), initialViewport);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('with auto-hide off the bar is docked and never hides',
      (tester) async {
    const size = Size(800, 600);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await redImage(tester, size);

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImagePreviewPage(
        mediaGroups: const [
          MediaGroup(
            primary: MediaFile(path: '/fixture.arw', kind: MediaKind.raw),
          ),
        ],
        initialIndex: 0,
        thumbnailResizeWidth: 256,
        imageStore: _FixtureImageStore(image),
        timestampRepository: TimestampRepository(),
        initialSettings: const ViewerSettings(previewAutoHideControls: false),
        onClose: () {},
        onRawViewModeChanged: (_) {},
        onPreviewFilmstripHeightChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();

    final fittedRect = tester.getRect(find.byType(InteractiveViewer));
    expect(fittedRect.top, kImagePreviewToolbarHeight);
    await tester.pump(previewChromeIdleHideDelay * 3);
    await tester.pumpAndSettle();
    expect(chromeOpacity(tester, find.byIcon(Icons.arrow_back)), 1);
    expect(chromeOpacity(tester, find.byIcon(Icons.zoom_in)), 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const navigationGroups = [
    MediaGroup(
      primary: MediaFile(path: '/fixture-1.jpg', kind: MediaKind.bitmap),
    ),
    MediaGroup(
      primary: MediaFile(path: '/fixture-2.jpg', kind: MediaKind.bitmap),
    ),
    MediaGroup(
      primary: MediaFile(path: '/fixture-3.jpg', kind: MediaKind.bitmap),
    ),
  ];

  Future<void> pumpPreview(
    WidgetTester tester, {
    required List<MediaGroup> mediaGroups,
  }) async {
    final cache = LruCache<String, ViewerImage>(1024,
        onEvict: (_, image) => image.dispose());
    addTearDown(cache.clear);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImagePreviewPage(
        mediaGroups: mediaGroups,
        initialIndex: 0,
        thumbnailResizeWidth: 256,
        imageStore: ImageStore(cache),
        timestampRepository: TimestampRepository(),
        initialSettings: const ViewerSettings(),
        onClose: () {},
        onRawViewModeChanged: (_) {},
        onPreviewFilmstripHeightChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('side arrows switch images and stay hidden until hovered',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPreview(tester, mediaGroups: navigationGroups);

    final previous = find.byKey(const ValueKey('preview-navigation-previous'));
    final next = find.byKey(const ValueKey('preview-navigation-next'));
    expect(previous, findsOneWidget);
    expect(next, findsOneWidget);
    expect(find.text('fixture-1.jpg'), findsOneWidget);

    double arrowOpacity(Finder arrow) => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(of: arrow, matching: find.byType(AnimatedOpacity))
              .first,
        )
        .opacity;

    expect(arrowOpacity(previous), 0);
    expect(arrowOpacity(next), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(next));
    await tester.pumpAndSettle();
    expect(arrowOpacity(next), 1);
    expect(arrowOpacity(previous), 0);

    await mouse.moveTo(const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(arrowOpacity(next), 0);

    // The first image has nowhere to go back to.
    expect(tester.widget<GestureDetector>(previous).onTap, isNull);
    expect(tester.widget<GestureDetector>(next).onTap, isNotNull);

    // The click target reaches well above the glyph itself.
    final nextRect = tester.getRect(next);
    await tester.tapAt(Offset(nextRect.center.dx, nextRect.top + 24));
    await tester.pumpAndSettle();
    expect(find.text('fixture-2.jpg'), findsOneWidget);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('fixture-3.jpg'), findsOneWidget);
    expect(tester.widget<GestureDetector>(next).onTap, isNull);

    await tester.tap(previous);
    await tester.pumpAndSettle();
    expect(find.text('fixture-2.jpg'), findsOneWidget);
  });

  testWidgets('side arrows are absent for a single image', (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpPreview(tester, mediaGroups: navigationGroups.take(1).toList());

    expect(find.byKey(const ValueKey('preview-navigation-previous')),
        findsNothing);
    expect(find.byKey(const ValueKey('preview-navigation-next')), findsNothing);
  });

  testWidgets('touch reveals hover controls and fades back after release',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: PreviewHoverReveal(
          restingOpacity: 0.2,
          child: SizedBox(width: 100, height: 100),
        ),
      ),
    ));

    double opacity() =>
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;
    expect(opacity(), 0.2);

    final touch = await tester.startGesture(
        tester.getCenter(find.byType(SizedBox)),
        kind: PointerDeviceKind.touch);
    await tester.pump();
    expect(opacity(), 1);

    // Held fingers keep the controls revealed indefinitely.
    await tester.pump(previewTouchRevealHoldDuration * 2);
    expect(opacity(), 1);

    await touch.up();
    await tester.pump(previewTouchRevealHoldDuration ~/ 2);
    expect(opacity(), 1);

    await tester.pump(previewTouchRevealHoldDuration);
    expect(opacity(), 0.2);

    // A fresh tap restarts the hold rather than inheriting an old timer.
    await tester.tapAt(tester.getCenter(find.byType(SizedBox)));
    await tester.pump();
    expect(opacity(), 1);
    await tester.pump(previewTouchRevealHoldDuration);
    expect(opacity(), 0.2);
  });

  group('auto-hiding chrome', () {
    Future<void> pumpRawPreview(WidgetTester tester,
        {VoidCallback? onClose}) async {
      const size = Size(800, 600);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final image = await redImage(tester, size);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImagePreviewPage(
          mediaGroups: const [
            MediaGroup(
              primary: MediaFile(path: '/fixture.arw', kind: MediaKind.raw),
            ),
          ],
          initialIndex: 0,
          thumbnailResizeWidth: 256,
          imageStore: _FixtureImageStore(image),
          timestampRepository: TimestampRepository(),
          initialSettings: const ViewerSettings(),
          onClose: onClose ?? () {},
          onRawViewModeChanged: (_) {},
          onPreviewFilmstripHeightChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> idle(WidgetTester tester) async {
      await tester.pump(previewChromeIdleHideDelay);
      await tester.pumpAndSettle();
    }

    bool cursorHidden(WidgetTester tester) => find
        .byWidgetPredicate((widget) =>
            widget is MouseRegion && widget.cursor == SystemMouseCursors.none)
        .evaluate()
        .isNotEmpty;

    testWidgets('hides every floating control together once the mouse rests',
        (tester) async {
      var closed = 0;
      await pumpRawPreview(tester, onClose: () => closed++);
      final back = find.byIcon(Icons.arrow_back);
      final zoomIn = find.byIcon(Icons.zoom_in);
      expect(chromeOpacity(tester, back), 1);
      expect(chromeOpacity(tester, zoomIn), 1);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 300));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(const Offset(410, 300));
      await tester.pump();

      await idle(tester);
      expect(chromeOpacity(tester, back), 0);
      expect(chromeOpacity(tester, zoomIn), 0);
      expect(cursorHidden(tester), isTrue);
      // The filmstrip is docked beside the photo, not over it: it stays.
      expect(find.byKey(const ValueKey('preview-filmstrip-panel')),
          findsOneWidget);

      // A hidden control cannot be clicked.
      final backCenter = tester.getCenter(back);
      await tester.tapAt(backCenter, kind: PointerDeviceKind.touch);
      await tester.pumpAndSettle();
      expect(closed, 0);
      // ...but that tap landed on the photo, which brings the chrome back.
      expect(chromeOpacity(tester, back), 1);

      await idle(tester);
      expect(chromeOpacity(tester, back), 0);
      await mouse.moveTo(const Offset(300, 300));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester, back), 1);
      expect(chromeOpacity(tester, zoomIn), 1);
      expect(cursorHidden(tester), isFalse);

      await tester.tap(back);
      expect(closed, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a control under the mouse keeps the chrome up',
        (tester) async {
      await pumpRawPreview(tester);
      final zoomIn = find.byIcon(Icons.zoom_in);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(400, 300));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(zoomIn));
      await tester.pump();

      await idle(tester);
      await idle(tester);
      expect(chromeOpacity(tester, zoomIn), 1);
      expect(chromeOpacity(tester, find.byIcon(Icons.arrow_back)), 1);

      // Leaving the control starts the countdown again.
      await mouse.moveTo(const Offset(400, 250));
      await tester.pump();
      await idle(tester);
      expect(chromeOpacity(tester, zoomIn), 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a touch tap on the photo toggles the chrome', (tester) async {
      await pumpRawPreview(tester);
      final back = find.byIcon(Icons.arrow_back);
      const photo = Offset(400, 250);

      await tester.tapAt(photo);
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester, back), 0);

      await tester.tapAt(photo);
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester, back), 1);

      // Tapping a control uses it without hiding the chrome.
      await tester.tap(find.byIcon(Icons.zoom_in));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester, back), 1);

      // A swipe is not a tap.
      await tester.dragFrom(photo, const Offset(0, 80));
      await tester.pumpAndSettle();
      expect(chromeOpacity(tester, back), 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
