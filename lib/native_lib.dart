import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

DynamicLibrary _openNativeLibrary() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('native_lib.dll');
  }

  if (Platform.isAndroid) {
    return DynamicLibrary.open('libnative_lib.so');
  }

  if (Platform.isMacOS) {
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final libraryPath = path.join(
      executableDir,
      '..',
      'Frameworks',
      'libnative_lib.dylib',
    );
    return DynamicLibrary.open(path.normalize(libraryPath));
  }

  if (Platform.isLinux) {
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final libraryPath = path.join(
      executableDir,
      'lib',
      'libnative_lib.so',
    );
    return DynamicLibrary.open(path.normalize(libraryPath));
  }

  return DynamicLibrary.process();
}

final DynamicLibrary nativeLib = _openNativeLibrary();

final class ThumbnailResult extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int format; // 0: JPEG, 1: RGB
}

final class ImageResult extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
}

// --- Windows (UTF-16 path) ---

typedef GetThumbnailC = Void Function(
    Pointer<Utf16> path, Pointer<ThumbnailResult> out);
typedef GetThumbnailDart = void Function(
    Pointer<Utf16> path, Pointer<ThumbnailResult> out);

typedef GetPreviewC = Void Function(
    Pointer<Utf16> path, Int32 halfSize, Pointer<ImageResult> out);
typedef GetPreviewDart = void Function(
    Pointer<Utf16> path, int halfSize, Pointer<ImageResult> out);

// --- POSIX (UTF-8 path) ---

typedef GetThumbnailC_Posix = Void Function(
    Pointer<Utf8> path, Pointer<ThumbnailResult> out);
typedef GetThumbnailDart_Posix = void Function(
    Pointer<Utf8> path, Pointer<ThumbnailResult> out);

typedef GetPreviewC_Posix = Void Function(
    Pointer<Utf8> path, Int32 halfSize, Pointer<ImageResult> out);
typedef GetPreviewDart_Posix = void Function(
    Pointer<Utf8> path, int halfSize, Pointer<ImageResult> out);

// --- Buffer variants ---

typedef GetThumbnailC_Buffer = Void Function(
    Pointer<Uint8> buffer, Int32 size, Pointer<ThumbnailResult> out);
typedef GetThumbnailDart_Buffer = void Function(
    Pointer<Uint8> buffer, int size, Pointer<ThumbnailResult> out);

typedef GetPreviewC_Buffer = Void Function(
    Pointer<Uint8> buffer, Int32 size, Int32 halfSize, Pointer<ImageResult> out);
typedef GetPreviewDart_Buffer = void Function(
    Pointer<Uint8> buffer, int size, int halfSize, Pointer<ImageResult> out);

// --- Free ---

typedef FreeBufferC = Void Function(Pointer<Uint8> buffer);
typedef FreeBufferDart = void Function(Pointer<Uint8> buffer);

class LibRawImage {
  final Uint8List data;
  final int width;
  final int height;
  final int format; // 0: JPEG, 1: BMP (Converted from RGB)

  LibRawImage(this.data, this.width, this.height, this.format);
}

class ViewerImage {
  final Uint8List data;
  final int? width;
  final int? height;
  final int? format;
  final bool isRaw;

  const ViewerImage({
    required this.data,
    required this.isRaw,
    this.width,
    this.height,
    this.format,
  });

  factory ViewerImage.fromRaw(LibRawImage image) {
    return ViewerImage(
      data: image.data,
      width: image.width,
      height: image.height,
      format: image.format,
      isRaw: true,
    );
  }

  factory ViewerImage.fromEncodedBytes(Uint8List data) {
    return ViewerImage(
      data: data,
      isRaw: false,
    );
  }
}

// BMP Header Generator
Uint8List _addBmpHeader(Uint8List rgbData, int width, int height) {
  final int dataSize = rgbData.length;
  // Padding for 4-byte alignment
  int padding = (4 - (width * 3) % 4) % 4;
  int stride = width * 3 + padding;
  final int fileSize = 54 + stride * height;

  final ByteData bd = ByteData(54);
  // Bitmap File Header
  bd.setUint8(0, 0x42); // 'B'
  bd.setUint8(1, 0x4D); // 'M'
  bd.setUint32(2, fileSize, Endian.little);
  bd.setUint32(6, 0, Endian.little); // Reserved
  bd.setUint32(10, 54, Endian.little); // Offset to pixel data

  // Bitmap Info Header
  bd.setUint32(14, 40, Endian.little); // Header size
  bd.setInt32(18, width, Endian.little);
  bd.setInt32(22, -height, Endian.little); // Negative height for top-down
  bd.setUint16(26, 1, Endian.little); // Planes
  bd.setUint16(28, 24, Endian.little); // BPP (RGB)
  bd.setUint32(30, 0, Endian.little); // Compression (BI_RGB)
  bd.setUint32(34, dataSize, Endian.little);
  bd.setInt32(38, 0, Endian.little); // X pixels per meter
  bd.setInt32(42, 0, Endian.little); // Y pixels per meter
  bd.setUint32(46, 0, Endian.little); // Colors used
  bd.setUint32(50, 0, Endian.little); // Important colors

  final Uint8List header = bd.buffer.asUint8List();

  if (padding == 0) {
    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(header);
    builder.add(rgbData);
    return builder.toBytes();
  } else {
    final BytesBuilder builder = BytesBuilder(copy: false);
    builder.add(header);
    for (int y = 0; y < height; y++) {
      final int start = y * width * 3;
      final int end = start + width * 3;
      builder.add(rgbData.sublist(start, end));
      for (int p = 0; p < padding; p++) {
        builder.addByte(0);
      }
    }
    return builder.toBytes();
  }
}

// Worker function for compute
LibRawImage? getThumbnailSync(String path) {
  final FreeBufferDart freeBufferFunc =
      nativeLib.lookup<NativeFunction<FreeBufferC>>('free_buffer').asFunction();

  final resultPtr = calloc<ThumbnailResult>();
  try {
    if (Platform.isWindows) {
      final GetThumbnailDart getThumbnailFunc = nativeLib
          .lookup<NativeFunction<GetThumbnailC>>('get_thumbnail')
          .asFunction();

      final pathPtr = path.toNativeUtf16();
      try {
        getThumbnailFunc(pathPtr, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } else {
      final GetThumbnailDart_Posix getThumbnailFunc = nativeLib
          .lookup<NativeFunction<GetThumbnailC_Posix>>('get_thumbnail')
          .asFunction();

      final pathPtr = path.toNativeUtf8();
      try {
        getThumbnailFunc(pathPtr, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }

      if (resultPtr.ref.data == nullptr) {
        // Fallback: Try reading file to memory and passing buffer (Android Scoped Storage)
        if (Platform.isAndroid) {
          try {
            final file = File(path);
            if (!file.existsSync()) return null;

            final bytes = file.readAsBytesSync();
            final bufferPtr = calloc<Uint8>(bytes.length);
            final bufferList = bufferPtr.asTypedList(bytes.length);
            bufferList.setAll(0, bytes);

            final GetThumbnailDart_Buffer getThumbnailBufferFunc = nativeLib
                .lookup<NativeFunction<GetThumbnailC_Buffer>>(
                    'get_thumbnail_from_buffer')
                .asFunction();

            try {
              getThumbnailBufferFunc(bufferPtr, bytes.length, resultPtr);
            } finally {
              calloc.free(bufferPtr);
            }
          } catch (e) {
            return null;
          }
        }
      }
    }

    return _processThumbnailResult(resultPtr.ref, freeBufferFunc);
  } finally {
    calloc.free(resultPtr);
  }
}

LibRawImage? _processThumbnailResult(
    ThumbnailResult result, FreeBufferDart freeBufferFunc) {
  if (result.data == nullptr || result.size == 0) {
    return null;
  }

  // Copy native data to Dart Uint8List
  final rawData = result.data.asTypedList(result.size);
  Uint8List finalData;
  int finalFormat = result.format;

  if (result.format == 1) {
    // RGB format, add BMP header here in isolate
    finalData =
        _addBmpHeader(Uint8List.fromList(rawData), result.width, result.height);
  } else {
    // JPEG, just copy
    finalData = Uint8List.fromList(rawData);
  }

  final width = result.width;
  final height = result.height;

  freeBufferFunc(result.data);

  return LibRawImage(finalData, width, height, finalFormat);
}

class PreviewRequest {
  final String path;
  final int halfSize;

  PreviewRequest(this.path, this.halfSize);
}

// Worker function for compute
LibRawImage? getPreviewSync(PreviewRequest request) {
  final FreeBufferDart freeBufferFunc =
      nativeLib.lookup<NativeFunction<FreeBufferC>>('free_buffer').asFunction();

  final resultPtr = calloc<ImageResult>();
  try {
    if (Platform.isWindows) {
      final GetPreviewDart getPreviewFunc = nativeLib
          .lookup<NativeFunction<GetPreviewC>>('get_preview')
          .asFunction();

      final pathPtr = request.path.toNativeUtf16();
      try {
        getPreviewFunc(pathPtr, request.halfSize, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } else {
      final GetPreviewDart_Posix getPreviewFunc = nativeLib
          .lookup<NativeFunction<GetPreviewC_Posix>>('get_preview')
          .asFunction();

      final pathPtr = request.path.toNativeUtf8();
      try {
        getPreviewFunc(pathPtr, request.halfSize, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }

      if (resultPtr.ref.data == nullptr) {
        // Fallback: Try buffer (Android)
        if (Platform.isAndroid) {
          try {
            final file = File(request.path);
            if (!file.existsSync()) return null;

            final bytes = file.readAsBytesSync();
            final bufferPtr = calloc<Uint8>(bytes.length);
            final bufferList = bufferPtr.asTypedList(bytes.length);
            bufferList.setAll(0, bytes);

            final GetPreviewDart_Buffer getPreviewBufferFunc = nativeLib
                .lookup<NativeFunction<GetPreviewC_Buffer>>(
                    'get_preview_from_buffer')
                .asFunction();

            try {
              getPreviewBufferFunc(
                  bufferPtr, bytes.length, request.halfSize, resultPtr);
            } finally {
              calloc.free(bufferPtr);
            }
          } catch (e) {
            return null;
          }
        }
      }
    }

    return _processPreviewResult(resultPtr.ref, freeBufferFunc);
  } finally {
    calloc.free(resultPtr);
  }
}

LibRawImage? _processPreviewResult(
    ImageResult result, FreeBufferDart freeBufferFunc) {
  if (result.data == nullptr || result.size == 0) {
    return null;
  }

  final rawData = result.data.asTypedList(result.size);

  // Preview is always RGB (1)
  final finalData =
      _addBmpHeader(Uint8List.fromList(rawData), result.width, result.height);

  final width = result.width;
  final height = result.height;

  freeBufferFunc(result.data);

  return LibRawImage(finalData, width, height, 1);
}
