import 'dart:ui' as ui;

import 'native_lib.dart';

/// A displayable image backed by a live [ui.Image] handle.
///
/// Ownership is explicit: whoever holds a [ViewerImage] must [dispose] it. Use
/// [clone] to hand an independent handle to something with its own lifetime —
/// the engine reference-counts the underlying pixels, so the last handle to go
/// releases the memory.
class ViewerImage {
  final ui.Image image;

  const ViewerImage({required this.image});

  int get width => image.width;
  int get height => image.height;

  /// Approximate bytes this image occupies, used for cache accounting.
  int get sizeInBytes => width * height * 4;

  /// A new handle onto the same underlying pixels. Cheap; must be disposed.
  ViewerImage clone() => ViewerImage(image: image.clone());

  void dispose() => image.dispose();
}

/// Turns a decoded [LibRawImage] into a [ui.Image].
///
/// For RGBA payloads this registers the existing pixels with the engine via
/// [ui.ImageDescriptor.raw] — no image-format parsing happens at all, which is
/// what removes the per-switch decode gap that showed up as a black flash.
/// Encoded (JPEG) payloads still go through the normal codec path.
///
/// [targetWidth] only ever downscales; upscaling a preview costs memory and
/// adds no detail.
Future<ui.Image> decodeToUiImage(LibRawImage image, {int? targetWidth}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(image.data);

  final ui.ImageDescriptor descriptor;
  if (image.isRgba) {
    descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: image.width,
      height: image.height,
      rowBytes: image.stride,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
  } else {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  }

  try {
    int? width;
    int? height;
    if (targetWidth != null &&
        targetWidth > 0 &&
        targetWidth < descriptor.width) {
      width = targetWidth;
      height = (descriptor.height * targetWidth / descriptor.width).round();
      if (height < 1) {
        height = 1;
      }
    }

    final codec = await descriptor.instantiateCodec(
      targetWidth: width,
      targetHeight: height,
    );
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}
