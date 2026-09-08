import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/bitmap_image_provider.dart';

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
