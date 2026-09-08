import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/bitmap_image_provider.dart';
import '../fixtures/animated_png.dart';

Future<int> _load(ImageProvider provider) async {
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
    return await result.future;
  } finally {
    stream.removeListener(listener);
  }
}

Future<Uint8List> _testPng() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawPaint(Paint()..color = const Color(0xffffffff));
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('heic_native');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  testWidgets('PNG frames have separate cache entries and never autoplay',
      (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('png-frames-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/three.png')
          .writeAsBytes(threeFramePng());
      expect(await bitmapFrameCount(file.path), 3);
      final colors = <List<int>>[];
      for (var index = 0; index < 3; index++) {
        final provider = ResizeImage(
            bitmapImageProvider(file.path, frameIndex: index),
            width: 128,
            policy: ResizeImagePolicy.fit);
        final result = Completer<void>();
        var emissions = 0;
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener((info, _) async {
          emissions++;
          try {
            final bytes = await info.image.toByteData();
            colors.add(bytes!.buffer.asUint8List().sublist(0, 4));
            expect(info.image.width, 2);
            if (!result.isCompleted) result.complete();
          } finally {
            info.dispose();
          }
        }, onError: (Object e, StackTrace? s) => result.completeError(e, s));
        stream.addListener(listener);
        try {
          await result.future;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          expect(emissions, 1);
        } finally {
          stream.removeListener(listener);
        }
      }
      expect(colors, [
        [255, 0, 0, 255],
        [0, 255, 0, 255],
        [0, 0, 255, 255]
      ]);
      expect(bitmapImageProvider(file.path),
          bitmapImageProvider(file.path, frameIndex: 0));
      expect(bitmapImageProvider(file.path),
          isNot(bitmapImageProvider(file.path, frameIndex: 1)));
      await expectLater(_load(bitmapImageProvider(file.path, frameIndex: 3)),
          throwsRangeError);
    });
  });

  const samplePath = String.fromEnvironment('PNG_SAMPLE_PATH');
  if (samplePath.isNotEmpty) {
    testWidgets('local three-frame PNG decodes at bounded preview width',
        (tester) async {
      await tester.runAsync(() async {
        expect(await bitmapFrameCount(samplePath), 3);
        for (var index = 0; index < 3; index++) {
          expect(
              await _load(resizedBitmapImageProvider(samplePath,
                  frameIndex: index,
                  width: 256,
                  policy: ResizeImagePolicy.fit)),
              256);
        }
      });
    });
  }

  test('standard formats retain FileImage cache identity', () {
    expect(bitmapImageProvider('/image.jpg'), FileImage(File('/image.jpg')));
    expect(
        bitmapImageProvider('/image.HEIC'), bitmapImageProvider('/image.HEIC'));
    expect(bitmapImageProvider('/image.HEIC'),
        isNot(FileImage(File('/image.HEIC'))));
  });

  testWidgets('different thumbnail sizes share an in-flight HEIC conversion',
      (tester) async {
    await tester.runAsync(() async {
      final png = await _testPng();
      var calls = 0;
      final entered = Completer<void>();
      final conversion = Completer<Uint8List>();
      messenger.setMockMethodCallHandler(channel, (call) {
        calls++;
        if (!entered.isCompleted) entered.complete();
        return conversion.future;
      });
      final small =
          _load(ResizeImage(bitmapImageProvider('/image.heic'), width: 128));
      await entered.future;
      final large =
          _load(ResizeImage(bitmapImageProvider('/image.heic'), width: 256));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      conversion.complete(png);
      expect(await small, greaterThan(0));
      expect(await large, greaterThan(0));
      expect(calls, 1);
    });
  });

  testWidgets('failed conversions do not poison the queue or prevent a retry',
      (tester) async {
    await tester.runAsync(() async {
      final png = await _testPng();
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (++calls == 1) {
          throw PlatformException(code: 'decode_failed');
        }
        return png;
      });
      await expectLater(_load(bitmapImageProvider('/retry.heif')),
          throwsA(isA<PlatformException>()));
      expect(await _load(bitmapImageProvider('/retry.heif')), greaterThan(0));
      expect(calls, 2);
    });
  });
}
