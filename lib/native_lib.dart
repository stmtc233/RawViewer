import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
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

/// Pixel/encoding layout of a [LibRawImage].
///
/// These values mirror the `format` field in the native `ThumbnailResult`.
abstract final class RawPixelFormat {
  /// Encoded image bytes (embedded JPEG preview), decoded by the engine.
  static const int encoded = 0;

  /// Tightly packed RGBA8888 pixels, ready for [ui.ImageDescriptor.raw].
  static const int rgba8888 = 2;
}

final class ThumbnailResult extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int format; // See RawPixelFormat.
  @Int32()
  external int stride;
}

final class ImageResult extends Struct {
  external Pointer<Uint8> data;
  @Int32()
  external int size;
  @Int32()
  external int width;
  @Int32()
  external int height;
  @Int32()
  external int stride;
}

// --- Windows (UTF-16 path) ---

typedef GetThumbnailC = Void Function(Pointer<Utf16> path,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);
typedef GetThumbnailDart = void Function(Pointer<Utf16> path,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);

typedef GetEmbeddedJpegC = Void Function(
    Pointer<Utf16> path, Pointer<ThumbnailResult> out);
typedef GetEmbeddedJpegDart = void Function(
    Pointer<Utf16> path, Pointer<ThumbnailResult> out);

// The native symbol name is still `get_preview`, but it semantically returns
// the decoded RAW layer rather than an arbitrary preview.
typedef GetDecodedRawPreviewC = Void Function(Pointer<Utf16> path,
    Int32 halfSize, Pointer<Void> cancelToken, Pointer<ImageResult> out);
typedef GetDecodedRawPreviewDart = void Function(Pointer<Utf16> path,
    int halfSize, Pointer<Void> cancelToken, Pointer<ImageResult> out);

// --- POSIX (UTF-8 path) ---

typedef GetThumbnailPosixC = Void Function(Pointer<Utf8> path,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);
typedef GetThumbnailPosixDart = void Function(Pointer<Utf8> path,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);

typedef GetEmbeddedJpegPosixC = Void Function(
    Pointer<Utf8> path, Pointer<ThumbnailResult> out);
typedef GetEmbeddedJpegPosixDart = void Function(
    Pointer<Utf8> path, Pointer<ThumbnailResult> out);

typedef GetDecodedRawPreviewPosixC = Void Function(Pointer<Utf8> path,
    Int32 halfSize, Pointer<Void> cancelToken, Pointer<ImageResult> out);
typedef GetDecodedRawPreviewPosixDart = void Function(Pointer<Utf8> path,
    int halfSize, Pointer<Void> cancelToken, Pointer<ImageResult> out);

// --- Buffer variants ---

typedef GetThumbnailBufferC = Void Function(Pointer<Uint8> buffer, Int32 size,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);
typedef GetThumbnailBufferDart = void Function(Pointer<Uint8> buffer, int size,
    Pointer<Void> cancelToken, Pointer<ThumbnailResult> out);

typedef GetEmbeddedJpegBufferC = Void Function(
    Pointer<Uint8> buffer, Int32 size, Pointer<ThumbnailResult> out);
typedef GetEmbeddedJpegBufferDart = void Function(
    Pointer<Uint8> buffer, int size, Pointer<ThumbnailResult> out);

typedef GetDecodedRawPreviewBufferC = Void Function(
    Pointer<Uint8> buffer,
    Int32 size,
    Int32 halfSize,
    Pointer<Void> cancelToken,
    Pointer<ImageResult> out);
typedef GetDecodedRawPreviewBufferDart = void Function(
    Pointer<Uint8> buffer,
    int size,
    int halfSize,
    Pointer<Void> cancelToken,
    Pointer<ImageResult> out);

// --- Free / cancellation ---

typedef FreeBufferC = Void Function(Pointer<Uint8> buffer);
typedef FreeBufferDart = void Function(Pointer<Uint8> buffer);

typedef CreateCancelTokenC = Pointer<Void> Function();
typedef CreateCancelTokenDart = Pointer<Void> Function();

typedef CancelTokenSetC = Void Function(Pointer<Void> token);
typedef CancelTokenSetDart = void Function(Pointer<Void> token);

typedef DestroyCancelTokenC = Void Function(Pointer<Void> token);
typedef DestroyCancelTokenDart = void Function(Pointer<Void> token);

// Symbol lookups are cached because `DynamicLibrary.lookup` is not free and the
// decode path runs on every thumbnail and every page switch.
final FreeBufferDart _freeBuffer =
    nativeLib.lookup<NativeFunction<FreeBufferC>>('free_buffer').asFunction();

final CreateCancelTokenDart _createCancelToken = nativeLib
    .lookup<NativeFunction<CreateCancelTokenC>>('create_cancel_token')
    .asFunction();

final CancelTokenSetDart _cancelTokenSet = nativeLib
    .lookup<NativeFunction<CancelTokenSetC>>('cancel_token_set')
    .asFunction();

final DestroyCancelTokenDart _destroyCancelToken = nativeLib
    .lookup<NativeFunction<DestroyCancelTokenC>>('destroy_cancel_token')
    .asFunction();

/// A native cancellation flag handed to LibRaw's progress callback.
///
/// Setting it makes an in-flight `unpack()`/`dcraw_process()` abort instead of
/// running to completion, which is what keeps fast page-flipping from pinning
/// the CPU on previews nobody will look at.
class RawCancelToken {
  Pointer<Void> _handle;
  bool _destroyed = false;

  RawCancelToken() : _handle = _createCancelToken();

  Pointer<Void> get handle => _handle;

  void cancel() {
    if (!_destroyed && _handle != nullptr) {
      _cancelTokenSet(_handle);
    }
  }

  /// Must be called exactly once, after the native call using this token has
  /// returned. The token outlives the call, never the other way around.
  void dispose() {
    if (_destroyed) return;
    _destroyed = true;
    if (_handle != nullptr) {
      _destroyCancelToken(_handle);
      _handle = nullptr;
    }
  }
}

/// A decoded RAW layer as it crosses the isolate boundary.
///
/// [data] is either encoded bytes ([RawPixelFormat.encoded]) or tightly packed
/// RGBA8888 pixels ([RawPixelFormat.rgba8888]).
class LibRawImage {
  final Uint8List data;
  final int width;
  final int height;
  final int format;
  final int stride;

  LibRawImage(this.data, this.width, this.height, this.format, this.stride);

  bool get isRgba => format == RawPixelFormat.rgba8888;
}

/// Returns the RAW thumbnail layer: the cheapest image LibRaw can produce for
/// this file.
///
/// Native code first tries to extract embedded preview data and then falls back
/// to a half-size RAW decode when the file has no embedded preview. The result
/// is therefore *not* necessarily the embedded JPEG — use
/// [getEmbeddedJpegImageSync] when that distinction matters.
///
/// This layer is only ever rendered at a bounded `ImageStore` target width
/// (grid tiles, filmstrip, the preview's first frame).
LibRawImage? getRawThumbnailSync(String filePath,
    {RawCancelToken? cancelToken}) {
  final token = cancelToken?.handle ?? nullptr;
  final resultPtr = calloc<ThumbnailResult>();
  try {
    if (Platform.isWindows) {
      final getThumbnailFunc = nativeLib
          .lookup<NativeFunction<GetThumbnailC>>('get_thumbnail')
          .asFunction<GetThumbnailDart>();

      final pathPtr = filePath.toNativeUtf16();
      try {
        getThumbnailFunc(pathPtr, token, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } else {
      final getThumbnailFunc = nativeLib
          .lookup<NativeFunction<GetThumbnailPosixC>>('get_thumbnail')
          .asFunction<GetThumbnailPosixDart>();

      final pathPtr = filePath.toNativeUtf8();
      try {
        getThumbnailFunc(pathPtr, token, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }

      if (resultPtr.ref.data == nullptr && Platform.isAndroid) {
        // Fallback: read the file into memory and pass a buffer, which is what
        // Android Scoped Storage paths require.
        _withAndroidFileBuffer(filePath, (bufferPtr, length) {
          final getThumbnailBufferFunc = nativeLib
              .lookup<NativeFunction<GetThumbnailBufferC>>(
                  'get_thumbnail_from_buffer')
              .asFunction<GetThumbnailBufferDart>();
          getThumbnailBufferFunc(bufferPtr, length, token, resultPtr);
        });
      }
    }

    return _processThumbnailResult(resultPtr.ref);
  } finally {
    calloc.free(resultPtr);
  }
}

/// Returns the JPEG embedded in a RAW file, without processing or re-encoding
/// it. Returns null when the file has no embedded JPEG.
///
/// Unlike [getRawThumbnailSync] this deliberately has **no fallback**: a null
/// result is the authoritative answer to "does this RAW carry an embedded
/// JPEG?", which is what lets the preview grey out that view mode.
///
/// Never call this on the main isolate — go through
/// `WorkerService.requestEmbeddedJpeg` (display) or [extractEmbeddedJpeg]
/// (file export).
LibRawImage? getEmbeddedJpegImageSync(String filePath) {
  final resultPtr = calloc<ThumbnailResult>();
  try {
    if (Platform.isWindows) {
      final getEmbeddedJpeg = nativeLib
          .lookup<NativeFunction<GetEmbeddedJpegC>>('get_embedded_jpeg')
          .asFunction<GetEmbeddedJpegDart>();
      final pathPtr = filePath.toNativeUtf16();
      try {
        getEmbeddedJpeg(pathPtr, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } else {
      final getEmbeddedJpeg = nativeLib
          .lookup<NativeFunction<GetEmbeddedJpegPosixC>>('get_embedded_jpeg')
          .asFunction<GetEmbeddedJpegPosixDart>();
      final pathPtr = filePath.toNativeUtf8();
      try {
        getEmbeddedJpeg(pathPtr, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }

      if (resultPtr.ref.data == nullptr && Platform.isAndroid) {
        _withAndroidFileBuffer(filePath, (bufferPtr, length) {
          final getEmbeddedJpegBuffer = nativeLib
              .lookup<NativeFunction<GetEmbeddedJpegBufferC>>(
                'get_embedded_jpeg_from_buffer',
              )
              .asFunction<GetEmbeddedJpegBufferDart>();
          getEmbeddedJpegBuffer(bufferPtr, length, resultPtr);
        });
      }
    }

    final image = _processThumbnailResult(resultPtr.ref);
    return image?.format == RawPixelFormat.encoded ? image : null;
  } finally {
    calloc.free(resultPtr);
  }
}

/// Returns the raw bytes of the embedded JPEG, for writing to a file.
Uint8List? getEmbeddedJpegSync(String filePath) =>
    getEmbeddedJpegImageSync(filePath)?.data;

/// Extracts an embedded JPEG on a helper isolate for use by the UI.
///
/// Export is a one-off user action that yields encoded bytes rather than a
/// `ui.Image`, so it runs on its own isolate instead of occupying a
/// [WorkerService] decode worker.
Future<Uint8List?> extractEmbeddedJpeg(String filePath) {
  return Isolate.run(() => getEmbeddedJpegSync(filePath));
}

/// Reads [filePath] into native memory and runs [action] over it.
///
/// Returns false when the file could not be read.
bool _withAndroidFileBuffer(
    String filePath, void Function(Pointer<Uint8> buffer, int length) action) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) return false;

    final bytes = file.readAsBytesSync();
    final bufferPtr = calloc<Uint8>(bytes.length);
    try {
      bufferPtr.asTypedList(bytes.length).setAll(0, bytes);
      action(bufferPtr, bytes.length);
      return true;
    } finally {
      calloc.free(bufferPtr);
    }
  } catch (_) {
    return false;
  }
}

LibRawImage? _processThumbnailResult(ThumbnailResult result) {
  if (result.data == nullptr || result.size <= 0) {
    return null;
  }

  // Copy out of native memory before handing ownership back to free_buffer.
  final data = Uint8List.fromList(result.data.asTypedList(result.size));
  final width = result.width;
  final height = result.height;
  final format = result.format;
  final stride = result.stride;

  _freeBuffer(result.data);

  return LibRawImage(data, width, height, format, stride);
}

class DecodedRawPreviewRequest {
  final String path;
  final int halfSize;

  DecodedRawPreviewRequest(this.path, this.halfSize);
}

// Returns the decoded RAW layer used as the final high-quality image.
//
// `halfSize` only affects this decoded RAW layer. The thumbnail layer is loaded
// through [getRawThumbnailSync].
LibRawImage? getDecodedRawPreviewSync(String filePath,
    {int halfSize = 1, RawCancelToken? cancelToken}) {
  final token = cancelToken?.handle ?? nullptr;
  final resultPtr = calloc<ImageResult>();
  try {
    if (Platform.isWindows) {
      final getPreviewFunc = nativeLib
          .lookup<NativeFunction<GetDecodedRawPreviewC>>('get_preview')
          .asFunction<GetDecodedRawPreviewDart>();

      final pathPtr = filePath.toNativeUtf16();
      try {
        getPreviewFunc(pathPtr, halfSize, token, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }
    } else {
      final getPreviewFunc = nativeLib
          .lookup<NativeFunction<GetDecodedRawPreviewPosixC>>('get_preview')
          .asFunction<GetDecodedRawPreviewPosixDart>();

      final pathPtr = filePath.toNativeUtf8();
      try {
        getPreviewFunc(pathPtr, halfSize, token, resultPtr);
      } finally {
        calloc.free(pathPtr);
      }

      if (resultPtr.ref.data == nullptr && Platform.isAndroid) {
        _withAndroidFileBuffer(filePath, (bufferPtr, length) {
          final getPreviewBufferFunc = nativeLib
              .lookup<NativeFunction<GetDecodedRawPreviewBufferC>>(
                  'get_preview_from_buffer')
              .asFunction<GetDecodedRawPreviewBufferDart>();
          getPreviewBufferFunc(bufferPtr, length, halfSize, token, resultPtr);
        });
      }
    }

    return _processPreviewResult(resultPtr.ref);
  } finally {
    calloc.free(resultPtr);
  }
}

LibRawImage? _processPreviewResult(ImageResult result) {
  if (result.data == nullptr || result.size <= 0) {
    return null;
  }

  final data = Uint8List.fromList(result.data.asTypedList(result.size));
  final width = result.width;
  final height = result.height;
  final stride = result.stride;

  _freeBuffer(result.data);

  return LibRawImage(data, width, height, RawPixelFormat.rgba8888, stride);
}
