import 'dart:async';

import 'lru_cache.dart';
import 'native_lib.dart';
import 'viewer_image.dart';
import 'worker_service.dart';

/// Which RAW layer an image represents.
enum RawLayer {
  /// Embedded preview, or a fast half-size decode when none exists.
  fastPreview,

  /// Full RAW decode used as the final high-quality image.
  decoded,
}

/// Owns decoding and caching of RAW previews as ready-to-paint `ui.Image`s.
///
/// Ownership rule: every [ViewerImage] handed out is owned by the caller and
/// must be disposed. The cache keeps its own master handle, so a widget
/// disposing its copy never invalidates the cache.
///
/// Caching decoded `ui.Image`s (rather than encoded bytes) is what lets a page
/// switch paint a cached preview on its very first frame, instead of showing a
/// gap while an async decode runs.
class ImageStore {
  ImageStore(this._cache);

  final LruCache<String, ViewerImage> _cache;

  /// Completion signals for in-flight decodes, so N widgets asking for the same
  /// image trigger one decode rather than N.
  final Map<String, Future<void>> _inFlight = {};

  /// Cache identity for one decoded image.
  ///
  /// [targetWidth] is part of the key: the grid and the full-screen preview want
  /// the same source at very different resolutions, and serving one from the
  /// other's entry would either show a blurry preview or hold thumbnail-grid
  /// memory at full size.
  static String cacheKey(
    String filePath,
    RawLayer layer, {
    int halfSize = 1,
    int? targetWidth,
  }) {
    final width = targetWidth ?? 0;
    return switch (layer) {
      RawLayer.fastPreview => '$filePath:fast-preview:$width',
      RawLayer.decoded => '$filePath:decoded-raw:$halfSize:$width',
    };
  }

  /// Returns a cached image immediately, or null when it is not resident.
  ///
  /// The returned handle is owned by the caller.
  ViewerImage? peek(
    String filePath,
    RawLayer layer, {
    int halfSize = 1,
    int? targetWidth,
  }) {
    return _cache
        .get(cacheKey(filePath, layer,
            halfSize: halfSize, targetWidth: targetWidth))
        ?.clone();
  }

  /// Loads an image, reusing the cache and any in-flight decode.
  ///
  /// Returns a handle owned by the caller, or null if decoding failed, the
  /// request was cancelled, or the result was too large to cache and another
  /// caller already claimed it.
  Future<ViewerImage?> load(
    String filePath,
    RawLayer layer, {
    int halfSize = 1,
    int? targetWidth,
    TaskPriority priority = TaskPriority.high,
    void Function(WorkerTask<LibRawImage?> task)? onTaskStarted,
  }) async {
    final key = cacheKey(filePath, layer,
        halfSize: halfSize, targetWidth: targetWidth);

    final cached = _cache.get(key);
    if (cached != null) return cached.clone();

    final existing = _inFlight[key];
    if (existing != null) {
      await existing;
      // Whoever ran the decode has populated the cache by now (or it failed).
      return _cache.get(key)?.clone();
    }

    final completer = Completer<void>();
    _inFlight[key] = completer.future;
    try {
      final task = layer == RawLayer.fastPreview
          ? WorkerService().requestRawFastPreview(filePath, priority: priority)
          : WorkerService().requestDecodedRawPreview(filePath,
              halfSize: halfSize, priority: priority);
      onTaskStarted?.call(task);

      final decoded = await task.result;
      if (decoded == null) return null;

      final uiImage = await decodeToUiImage(decoded, targetWidth: targetWidth);
      final master = ViewerImage(image: uiImage);

      // An image larger than the entire budget can never stay resident, so skip
      // the cache and hand ownership straight to this caller.
      if (master.sizeInBytes > _cache.maximumSize) {
        return master;
      }

      // Clone before inserting: put() may evict (and dispose) this very entry.
      final handle = master.clone();
      _cache.put(key, master);
      return handle;
    } catch (_) {
      return null;
    } finally {
      _inFlight.remove(key);
      completer.complete();
    }
  }
}
