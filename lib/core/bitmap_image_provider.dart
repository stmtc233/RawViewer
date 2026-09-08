import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:heic_native/heic_native.dart';
import 'package:path/path.dart' as path;

/// HEIC conversion is an SDR fallback. HDR previews read the original file.
ImageProvider bitmapImageProvider(String filePath) {
  final extension = path.extension(filePath).toLowerCase();
  final file = File(filePath);
  return extension == '.heic' || extension == '.heif'
      ? _HeicFileImage(file)
      : FileImage(file);
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
