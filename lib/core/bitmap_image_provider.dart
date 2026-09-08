import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:heic_native/heic_native.dart';
import 'package:path/path.dart' as path;

/// HEIC conversion is an SDR fallback. HDR previews read the original file.
ImageProvider bitmapImageProvider(String filePath,
    {int frameIndex = 0, int? decodeWidth}) {
  final extension = path.extension(filePath).toLowerCase();
  final file = File(filePath);
  if (extension == '.png') return _PngFrameImage(file, frameIndex, decodeWidth);
  return extension == '.heic' || extension == '.heif'
      ? _HeicFileImage(file)
      : FileImage(file);
}

ResizeImage resizedBitmapImageProvider(
  String filePath, {
  required int width,
  int frameIndex = 0,
  ResizeImagePolicy policy = ResizeImagePolicy.exact,
}) =>
    ResizeImage(
        bitmapImageProvider(filePath,
            frameIndex: frameIndex, decodeWidth: width),
        width: width,
        policy: policy);

/// Counts PNG frames without decoding full-resolution pixels.
Future<int> bitmapFrameCount(String filePath) async {
  if (path.extension(filePath).toLowerCase() != '.png') return 1;
  final buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      final codec =
          await descriptor.instantiateCodec(targetWidth: 1, targetHeight: 1);
      try {
        return codec.frameCount;
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

/// APNGs are browsed as still frames; thumbnails always request frame zero.
class _PngFrameImage extends FileImage {
  final int frameIndex;
  final int? decodeWidth;

  const _PngFrameImage(super.file, this.frameIndex, this.decodeWidth);

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) =>
      _StaticFrameCompleter(_loadFrame(decode));

  Future<ImageInfo> _loadFrame(ImageDecoderCallback decode) async {
    final codec =
        await decode(await ui.ImmutableBuffer.fromFilePath(file.path));
    try {
      if (frameIndex < 0 || frameIndex >= codec.frameCount) {
        throw RangeError.range(
            frameIndex, 0, codec.frameCount - 1, 'frameIndex');
      }
      // The codec handles APNG frame blending and disposal semantics.
      for (var index = 0; index < frameIndex; index++) {
        (await codec.getNextFrame()).image.dispose();
      }
      final frame = await codec.getNextFrame();
      final width = decodeWidth;
      if (width != null && width > 0 && frame.image.width > width) {
        // Flutter's animated PNG codec can ignore targetWidth. Keep only the
        // selected, downscaled frame in the image cache.
        final image = frame.image;
        final height =
            (image.height * width / image.width).round().clamp(1, image.height);
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawImageRect(
            image,
            ui.Rect.fromLTWH(
                0, 0, image.width.toDouble(), image.height.toDouble()),
            ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
            ui.Paint()..filterQuality = ui.FilterQuality.medium);
        final picture = recorder.endRecording();
        try {
          return ImageInfo(
              image: await picture.toImage(width, height),
              scale: scale,
              debugLabel: file.path);
        } finally {
          picture.dispose();
          image.dispose();
        }
      }
      return ImageInfo(image: frame.image, scale: scale, debugLabel: file.path);
    } finally {
      codec.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _PngFrameImage &&
      other.file.path == file.path &&
      other.scale == scale &&
      other.frameIndex == frameIndex &&
      other.decodeWidth == decodeWidth;

  @override
  int get hashCode => Object.hash(file.path, scale, frameIndex, decodeWidth);
}

class _StaticFrameCompleter extends OneFrameImageStreamCompleter {
  bool _disposed = false;

  _StaticFrameCompleter(super.image);

  @override
  void onDisposed() {
    _disposed = true;
    super.onDisposed();
  }

  @override
  void setImage(ImageInfo image) {
    // An evicted frame can finish decoding after navigation or cache cleanup.
    if (_disposed) {
      image.dispose();
    } else {
      super.setImage(image);
    }
  }
}

class _HeicFileImage extends FileImage {
  const _HeicFileImage(super.file);

  static final _conversions = <String, Future<Uint8List>>{};
  static Future<void> _conversionTail = Future<void>.value();

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: key.scale,
      debugLabel: key.file.path,
    );
  }

  Future<ui.Codec> _load(FileImage key, ImageDecoderCallback decode) async {
    try {
      final bytes = await _conversions.putIfAbsent(key.file.path, () {
        final conversion =
            _conversionTail.then((_) => HeicNative.convertToBytes(
                  key.file.path,
                  compressionLevel: 0,
                ));
        // Bound native working memory to one full-resolution conversion.
        _conversionTail = conversion.then<void>((_) {}, onError: (Object _) {});
        return conversion.whenComplete(() {
          _conversions.remove(key.file.path);
        });
      });
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(key);
      rethrow;
    }
  }
}
