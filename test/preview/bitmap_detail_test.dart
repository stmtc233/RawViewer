import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/raw_view_mode.dart';
import 'package:rawviewer/core/bitmap_image_provider.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/preview/single_image_preview.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';
import '../fixtures/animated_png.dart';

ResizeImage _detailProvider(WidgetTester tester) =>
    tester.widgetList<Image>(find.byType(Image)).last.image as ResizeImage;

Future<int> _decodedWidth(WidgetTester tester, ImageProvider provider) async {
  return (await tester.runAsync(() async {
    final result = Completer<int>();
    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((info, _) {
      if (!result.isCompleted) result.complete(info.image.width);
      info.dispose();
    }, onError: (Object error, StackTrace? stack) {
      if (!result.isCompleted) result.completeError(error, stack);
    });
    stream.addListener(listener);
    try {
      return await result.future.timeout(const Duration(seconds: 10));
    } finally {
      stream.removeListener(listener);
    }
  }))!;
}

void main() {
  testWidgets(
      'multi-frame PNG exposes bounded manual navigation and resets for another file',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('preview-frames-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/three.png')
      ..writeAsBytesSync(threeFramePng());
    final second = File('${directory.path}/other.png')
      ..writeAsBytesSync(threeFramePng());
    final scrolling = ValueNotifier(false);
    addTearDown(scrolling.dispose);
    final store = ImageStore(LruCache<String, ViewerImage>(1024,
        onEvict: (_, image) => image.dispose()));
    Widget preview(String path) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SingleImagePreview(
            mediaGroup: MediaGroup(
                primary: MediaFile(path: path, kind: MediaKind.bitmap)),
            thumbnailResizeWidth: 128,
            previewThumbnailResizeWidth: 256,
            imageStore: store,
            settings: const ViewerSettings(),
            rotationQuarterTurns: 0,
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
        );
    await tester.runAsync(() async {
      await tester.pumpWidget(preview(file.path));
      await _loadFramesReady(tester);
    });
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_left))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Next frame'));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    expect(
        _detailProvider(tester).imageProvider,
        bitmapImageProvider(file.path,
            frameIndex: 1, decodeWidth: _detailProvider(tester).width));
    await tester.tap(find.byTooltip('Next frame'));
    await tester.pump();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right))
            .onPressed,
        isNull);
    await tester.tap(find.byTooltip('Previous frame'));
    await tester.pump();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.pumpWidget(preview(second.path));
      await _loadFramesReady(tester);
    });
    await tester.pump();
    expect(find.text('1 / 3'), findsOneWidget);
    expect(
        _detailProvider(tester).imageProvider,
        bitmapImageProvider(second.path,
            decodeWidth: _detailProvider(tester).width));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {});
    expect(tester.takeException(), isNull);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  for (final paired in [false, true]) {
    testWidgets(
        '${paired ? 'paired' : 'standalone'} bitmap loads original '
        'detail after zoom settles and retains it when zooming out',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('bitmap-detail-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/wide.png');
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawPaint(Paint()..color = Colors.red);
        final picture = recorder.endRecording();
        final image = await picture.toImage(6000, 80);
        picture.dispose();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await file.writeAsBytes(bytes!.buffer.asUint8List());
      });
      final scrolling = ValueNotifier<bool>(false);
      addTearDown(scrolling.dispose);
      final store = ImageStore(LruCache<String, ViewerImage>(1024,
          onEvict: (_, image) => image.dispose()));
      final bitmap = MediaFile(path: file.path, kind: MediaKind.bitmap);
      final group = MediaGroup(
        primary: paired
            ? const MediaFile(path: '/fixture.arw', kind: MediaKind.raw)
            : bitmap,
        pairedJpeg: paired ? bitmap : null,
      );

      Widget preview({bool active = true}) => MaterialApp(
            home: SingleImagePreview(
              mediaGroup: group,
              thumbnailResizeWidth: 256,
              previewThumbnailResizeWidth: 512,
              imageStore: store,
              settings: const ViewerSettings(),
              rotationQuarterTurns: 0,
              viewMode:
                  paired ? RawViewMode.pairedJpeg : RawViewMode.decodedRaw,
              onResetRotationRequested: () {},
              onSwitchRequest: (_) {},
              onTrackpadPanStart: (_) {},
              onTrackpadPanUpdate: (_) {},
              onTrackpadPanEnd: (_) {},
              onTrackpadPanCancel: () {},
              isActive: active,
              showPreviewOverview: false,
              overviewBottomInset: 0,
              isFastScrolling: scrolling,
            ),
          );

      await tester.runAsync(() => tester.pumpWidget(preview()));
      final initial = _detailProvider(tester);
      expect(await _decodedWidth(tester, initial), lessThan(6000));
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final controller = viewer.transformationController!;
      controller.value = Matrix4.diagonal3Values(4, 4, 1);
      await tester.pump();
      expect(_detailProvider(tester), initial);
      controller.value = Matrix4.diagonal3Values(8, 8, 1);
      await tester.runAsync(() => tester.pump(const Duration(seconds: 1)));
      final detail = _detailProvider(tester);
      expect(detail.width, greaterThan(4096));
      expect(await _decodedWidth(tester, detail), 6000);
      await tester.pump();
      expect(
        tester.widgetList<RawImage>(find.byType(RawImage)).any(
              (image) => image.image?.width == 6000,
            ),
        isTrue,
      );

      controller.value = Matrix4.identity();
      await tester.pump(const Duration(seconds: 1));
      expect(_detailProvider(tester), detail);

      // A page switch must discard a pending upgrade and its retained tier.
      controller.value = Matrix4.diagonal3Values(16, 16, 1);
      await tester.pumpWidget(preview(active: false));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(preview());
      expect(_detailProvider(tester), initial);

      controller.value = Matrix4.diagonal3Values(8, 8, 1);
      scrolling.value = true;
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(Image), findsOneWidget);
      scrolling.value = false;
      await tester.pump(const Duration(seconds: 1));
      expect(_detailProvider(tester).width, greaterThan(4096));

      final state = tester.state<SingleImagePreviewState>(
        find.byType(SingleImagePreview),
      );
      for (var i = 0; i < 20; i++) {
        state.zoomIn();
      }
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(5));
      expect(controller.value.getMaxScaleOnAxis(), kMaxPreviewScale);
      expect(viewer.maxScale, kMaxPreviewScale);

      // Disposing with a queued detail upgrade must not fire setState later.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    });
  }
}

Future<void> _loadFramesReady(WidgetTester tester) async {
  for (var i = 0; i < 100 && find.text('1 / 3').evaluate().isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump();
  }
}
