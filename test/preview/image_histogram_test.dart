import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/raw_view_mode.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/preview/image_histogram.dart';
import 'package:rawviewer/preview/scroll_gesture_coalescer.dart';
import 'package:rawviewer/preview/single_image_preview.dart';
import 'package:rawviewer/preview/widgets/histogram_image_observer.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';

Future<ui.Image> _solid(ui.Color color, {int width = 4, int height = 4}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(color, ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(width, height);
  } finally {
    picture.dispose();
  }
}

Future<void> _waitForHistogram(
    WidgetTester tester, List<HistogramSnapshot> values) async {
  await tester.pump(const Duration(milliseconds: 160));
  await tester.runAsync(() async {
    for (var i = 0; i < 200 && !values.any((v) => v.data != null); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await tester.pump();
    }
  });
  expect(values.any((v) => v.data != null), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('counts RGB endpoints, luminance and excludes transparent pixels', () {
    final result = histogramFromRgba(Uint8List.fromList([
      0,
      0,
      0,
      255,
      255,
      255,
      255,
      255,
      255,
      0,
      0,
      128,
      0,
      255,
      0,
      255,
      0,
      0,
      255,
      255,
      17,
      18,
      19,
      0,
    ]))!;
    for (final channel in [result.red, result.green, result.blue]) {
      expect(channel[0], 3);
      expect(channel[255], 2);
      expect(channel.reduce((a, b) => a + b), 5);
    }
    expect(result.luminance[0], 1);
    expect(result.luminance[255], 1);
    expect(result.luminance[54], 1);
    expect(result.luminance[182], 1);
    expect(result.luminance[18], 1);
    expect(histogramFromRgba(Uint8List(0)), isNull);
    expect(histogramFromRgba(Uint8List(4)), isNull);
    expect(() => histogramFromRgba(Uint8List(3)), throwsArgumentError);
  });

  test('readback is bounded and owns a clone across async work', () async {
    final image =
        await _solid(const ui.Color(0xFFFF0000), width: 1024, height: 2048);
    final result = histogramForImage(image);
    image.dispose();
    final data = (await result)!;
    expect(data.red[255], 256 * 512);
    expect(data.green[0], 256 * 512);
    expect(data.blue[0], 256 * 512);
  });

  testWidgets(
      'observer discards in-flight results and releases its image after removal',
      (tester) async {
    final red =
        (await tester.runAsync(() => _solid(const ui.Color(0xFFFF0000))))!;
    final blue =
        (await tester.runAsync(() => _solid(const ui.Color(0xFF0000FF))))!;
    addTearDown(red.dispose);
    addTearDown(blue.dispose);
    final values = <HistogramSnapshot>[];
    Widget observer(ui.Image image) =>
        HistogramImageObserver(image: image, onChanged: values.add);
    await tester.pumpWidget(observer(red));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpWidget(observer(blue));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.runAsync(() async {
      // Wait for engine readback and the compute isolate, then flush publication.
      for (var i = 0; i < 100 && !values.any((v) => v.data != null); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    final ready = values.where((v) => v.data != null).toList();
    expect(ready, hasLength(1));
    expect(ready.single.data!.blue[255], 16);
    expect(ready.single.data!.red[255], 0);
    await tester.pumpWidget(const SizedBox());
    expect(red.debugGetOpenHandleStackTraces(), hasLength(1));
    expect(blue.debugGetOpenHandleStackTraces(), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'preview histogram follows RAW modes and bitmap sources only when enabled',
      (tester) async {
    final directory = Directory.systemTemp.createTempSync('histogram-preview-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final bitmapFile = File('${directory.path}/paired.png');
    final red =
        (await tester.runAsync(() => _solid(const ui.Color(0xFFFF0000))))!;
    final blue =
        (await tester.runAsync(() => _solid(const ui.Color(0xFF0000FF))))!;
    await tester.runAsync(() async {
      final green = await _solid(const ui.Color(0xFF00FF00));
      try {
        final bytes = await green.toByteData(format: ui.ImageByteFormat.png);
        await bitmapFile.writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        green.dispose();
      }
    });
    final cache = LruCache<String, ViewerImage>(1024 * 1024,
        onEvict: (_, image) => image.dispose());
    addTearDown(cache.clear);
    const rawPath = '/histogram-fixture.arw';
    cache.put(
        ImageStore.cacheKey(rawPath, RawLayer.thumbnail, targetWidth: 128),
        ViewerImage(image: red.clone()));
    cache.put(ImageStore.cacheKey(rawPath, RawLayer.embeddedJpeg),
        ViewerImage(image: red));
    cache.put(ImageStore.cacheKey(rawPath, RawLayer.decoded),
        ViewerImage(image: blue));
    final store = ImageStore(cache);
    final scrolling = ValueNotifier(false);
    addTearDown(scrolling.dispose);
    final values = <HistogramSnapshot>[];
    final bitmap = MediaFile(path: bitmapFile.path, kind: MediaKind.bitmap);
    Widget preview(RawViewMode mode,
            {bool enabled = true, bool active = true, bool raw = true}) =>
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SingleImagePreview(
            key: ValueKey(raw),
            mediaGroup: MediaGroup(
              primary: raw
                  ? const MediaFile(path: rawPath, kind: MediaKind.raw)
                  : bitmap,
              pairedJpeg: raw ? bitmap : null,
            ),
            thumbnailResizeWidth: 128,
            previewThumbnailResizeWidth: 256,
            imageStore: store,
            settings: const ViewerSettings(),
            rotationQuarterTurns: 0,
            viewMode: mode,
            onResetRotationRequested: () {},
            onSwitchRequest: (_) {},
            scrollGesture: ScrollGestureCoalescer(),
            onTrackpadPanStart: (_) {},
            onTrackpadPanUpdate: (_) {},
            onTrackpadPanEnd: (_) {},
            onTrackpadPanCancel: () {},
            isActive: active,
            showPreviewOverview: false,
            overviewBottomInset: 0,
            isFastScrolling: scrolling,
            showHdr: false,
            onHistogramChanged: enabled ? values.add : null,
          ),
        );
    await tester.pumpWidget(preview(RawViewMode.embeddedJpeg, enabled: false));
    await tester.pump();
    expect(find.byType(HistogramImageObserver), findsNothing);
    expect(values, isEmpty);
    for (final mode in [
      RawViewMode.embeddedJpeg,
      RawViewMode.decodedRaw,
      RawViewMode.embeddedJpeg,
      RawViewMode.pairedJpeg
    ]) {
      values.clear();
      await tester.pumpWidget(preview(mode));
      await tester.pump();
      await _waitForHistogram(tester, values);
      final data = values.last.data!;
      expect(
          mode == RawViewMode.pairedJpeg
              ? data.green[255]
              : mode == RawViewMode.decodedRaw
                  ? data.blue[255]
                  : data.red[255],
          16);
    }
    scrolling.value = true;
    await tester.pump();
    expect(find.byType(HistogramImageObserver), findsNothing);
    scrolling.value = false;
    await tester.pumpWidget(preview(RawViewMode.pairedJpeg, active: false));
    expect(find.byType(HistogramImageObserver), findsNothing);
    values.clear();
    await tester.pumpWidget(preview(RawViewMode.decodedRaw, raw: false));
    await _waitForHistogram(tester, values);
    expect(values.last.data!.green[255], 16);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed bitmap and disposal do not publish stale results',
      (tester) async {
    final values = <HistogramSnapshot>[];
    await tester.pumpWidget(HistogramImageObserver(
        provider: MemoryImage(Uint8List.fromList([1, 2, 3])),
        onChanged: values.add));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !values.any((v) => !v.isLoading); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
      }
    });
    expect(values.last.isLoading, isFalse);
    expect(values.last.data, isNull);
    await tester.pumpWidget(HistogramImageObserver(
        provider: MemoryImage(Uint8List.fromList([4, 5, 6])),
        onChanged: values.add));
    await tester.pumpWidget(const SizedBox());
    final count = values.length;
    await tester.pump(const Duration(seconds: 1));
    expect(values, hasLength(count));
    expect(tester.takeException(), isNull);
  });
}
