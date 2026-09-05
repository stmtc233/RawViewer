import 'dart:ui' as ui;

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
import 'package:rawviewer/preview/widgets/preview_filmstrip.dart';
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
          void Function(WorkerTask<LibRawImage?> task)? onTaskStarted}) async =>
      image.clone();
}

void main() {
  for (final size in [const Size(800, 600), const Size(360, 800)]) {
    testWidgets('image fits between bars and zooms beneath them at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
              initialSettings: const ViewerSettings(
                previewOverlayOpacity: 0.5,
                previewToolbarOpacity: 0.3,
                previewFilmstripOpacity: 0.6,
              ),
              onClose: () {},
              onRawViewModeChanged: (_) {},
              onPreviewFilmstripHeightChanged: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      double restingOpacityFor(Finder child) => tester
          .widget<PreviewHoverReveal>(
            find
                .ancestor(of: child, matching: find.byType(PreviewHoverReveal))
                .first,
          )
          .restingOpacity;
      expect(restingOpacityFor(find.byIcon(Icons.arrow_back)), 0.3);
      expect(restingOpacityFor(find.byType(PreviewFilmstrip)), 0.6);
      expect(restingOpacityFor(find.byIcon(Icons.zoom_in)), 0.5);

      Future<void> expectImageBehindBars({required bool visible}) async {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final screenshot = await boundary.toImage();
          try {
            final pixels = (await screenshot.toByteData())!;
            // Sample empty bar background, away from buttons and thumbnails.
            for (final y in [
              safePadding.top.toInt() + 2,
              size.height.toInt() - 8
            ]) {
              final offset = (y * screenshot.width + 2) * 4;
              final redExcess =
                  pixels.getUint8(offset) - pixels.getUint8(offset + 1);
              expect(redExcess, visible ? greaterThan(80) : lessThan(20),
                  reason: 'Image behind the bar at y=$y: visible=$visible');
            }
            final centerOffset = ((screenshot.height ~/ 2) * screenshot.width +
                    screenshot.width ~/ 2) *
                4;
            expect(pixels.getUint8(centerOffset),
                greaterThan(pixels.getUint8(centerOffset + 1) + 80));
          } finally {
            screenshot.dispose();
          }
        });
      }

      Future<void> zoomIn() async {
        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byIcon(Icons.zoom_in));
          await tester.pumpAndSettle();
        }
      }

      void expectFittedViewport() {
        final fittedRect = tester.getRect(find.byType(InteractiveViewer));
        expect(fittedRect.top, safePadding.top + kImagePreviewToolbarHeight);
        expect(
            fittedRect.bottom,
            tester
                .getTopLeft(
                  find.byKey(const ValueKey('preview-filmstrip-panel')),
                )
                .dy);
      }

      await expectImageBehindBars(visible: false);
      expectFittedViewport();
      final initialViewport = tester.getRect(find.byType(PageView));
      expect(initialViewport, Offset.zero & size);
      await zoomIn();
      await expectImageBehindBars(visible: true);
      await tester.tap(find.byIcon(Icons.filter_center_focus));
      await tester.pumpAndSettle();
      await expectImageBehindBars(visible: false);

      await tester.drag(
        find.byKey(const ValueKey('preview-filmstrip-resize-handle')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(PageView)), initialViewport);
      expectFittedViewport();
      await expectImageBehindBars(visible: false);

      await zoomIn();
      await expectImageBehindBars(visible: true);
      final overviewRect = tester.getRect(find.byType(PreviewOverviewMap));
      expect(restingOpacityFor(find.byType(PreviewOverviewMap)), 0.5);
      final controlsRect = tester.getRect(find.byIcon(Icons.zoom_in));
      final filmstripRect = tester.getRect(
        find.byKey(const ValueKey('preview-filmstrip-panel')),
      );
      expect(overviewRect.bottom, lessThan(controlsRect.top));
      expect(controlsRect.bottom, lessThan(filmstripRect.top));

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ImagePreviewPage)),
      )!;
      await tester.tap(find.byTooltip(l10n.previewDisplayControlsTooltip));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.previewFilmstripTitle));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('preview-filmstrip-panel')), findsNothing);
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
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
