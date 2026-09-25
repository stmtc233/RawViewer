import 'dart:async';

import 'lru_cache.dart';
import 'native_lib.dart';
import 'viewer_image.dart';
import 'worker_service.dart';

/// Which RAW layer an image represents.
enum RawLayer {
  /// The cheapest image LibRaw can produce: embedded preview data when the file
  /// has it, a half-size RAW decode otherwise.
  ///
  /// Only ever requested at a bounded [ImageStore.load] `targetWidth` — grid
  /// tiles, filmstrip, and the preview's first frame.
  thumbnail,

  /// The JPEG embedded in the RAW container, with no fallback. A failed load
  /// means the file carries no embedded JPEG.
  embeddedJpeg,

  /// Full RAW decode used as the final high-quality image.
  decoded,
}

/// A caller's claim on a shared decode's place in the queue.
///
/// Withdrawing never cancels anything: the decode still runs and lands in the
/// cache, so other widgets sharing it are unaffected. Once every high-priority
/// caller has withdrawn, a decode that has not started yet drops back to low
/// priority, so work that is still wanted runs first.
class ImageLoadInterest {
  void Function()? _withdraw;
  bool _isWithdrawn = false;

  bool get isWithdrawn => _isWithdrawn;

  void withdraw() {
    _isWithdrawn = true;
    final withdraw = _withdraw;
    _withdraw = null;
    withdraw?.call();
  }
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
  final Map<String, WorkerTask<LibRawImage?>> _inFlightTasks = {};

  /// High-priority callers still waiting on each in-flight decode.
  final Map<String, int> _highPriorityClaims = {};

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
      RawLayer.thumbnail => '$filePath:thumbnail:$width',
      RawLayer.embeddedJpeg => '$filePath:embedded-jpeg:$width',
      RawLayer.decoded => '$filePath:decoded-raw:$halfSize:$width',
    };
  }

  static final RegExp _fullScreenKeySuffix =
      RegExp(r':(embedded-jpeg:\d+|decoded-raw:\d+:\d+)$');

  /// Whether [key] (from [cacheKey]) holds a full-screen layer rather than the
  /// bounded-width thumbnail layer.
  ///
  /// Matched on the suffix [cacheKey] appends, so a file path containing a
  /// layer name cannot be misread.
  static bool isFullScreenKey(String key) => _fullScreenKeySuffix.hasMatch(key);

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
  ///
  /// A high-priority caller that stops caring before the result arrives can
  /// give up its place in the queue through [interest].
  Future<ViewerImage?> load(
    String filePath,
    RawLayer layer, {
    int halfSize = 1,
    int? targetWidth,
    TaskPriority priority = TaskPriority.high,
    void Function(WorkerTask<LibRawImage?> task)? onTaskStarted,
    ImageLoadInterest? interest,
  }) async {
    final key =
        cacheKey(filePath, layer, halfSize: halfSize, targetWidth: targetWidth);

    final cached = _cache.get(key);
    if (cached != null) return cached.clone();

    if (priority != TaskPriority.high) {
      return _loadUncached(key, filePath, layer,
          halfSize: halfSize,
          targetWidth: targetWidth,
          priority: priority,
          onTaskStarted: onTaskStarted);
    }

    _highPriorityClaims.update(key, (count) => count + 1, ifAbsent: () => 1);
    var claimed = true;
    void release() {
      if (!claimed) return;
      claimed = false;
      _releaseHighPriority(key);
    }

    interest?._withdraw = release;
    try {
      return await _loadUncached(key, filePath, layer,
          halfSize: halfSize,
          targetWidth: targetWidth,
          priority: priority,
          onTaskStarted: onTaskStarted);
    } finally {
      release();
    }
  }

  void _releaseHighPriority(String key) {
    final remaining = (_highPriorityClaims[key] ?? 1) - 1;
    if (remaining > 0) {
      _highPriorityClaims[key] = remaining;
      return;
    }
    _highPriorityClaims.remove(key);
    // Gone once the decode has finished, so only a still-queued one moves.
    final task = _inFlightTasks[key];
    if (task != null) WorkerService().demoteRequest(task.requestId);
  }

  Future<ViewerImage?> _loadUncached(
    String key,
    String filePath,
    RawLayer layer, {
    required int halfSize,
    required int? targetWidth,
    required TaskPriority priority,
    required void Function(WorkerTask<LibRawImage?> task)? onTaskStarted,
  }) async {
    final existing = _inFlight[key];
    if (existing != null) {
      // A neighbour may have started this decode at low priority just before
      // it became the active page. Promote the shared queued task instead of
      // waiting behind stale preloads.
      if (priority == TaskPriority.high) {
        final task = _inFlightTasks[key];
        if (task != null) {
          WorkerService().bumpRequest(task.requestId, TaskPriority.high);
        }
      }
      await existing;
      // Whoever ran the decode has populated the cache by now (or it failed).
      return _cache.get(key)?.clone();
    }

    final completer = Completer<void>();
    _inFlight[key] = completer.future;
    try {
      final service = WorkerService();
      final task = switch (layer) {
        RawLayer.thumbnail =>
          service.requestRawThumbnail(filePath, priority: priority),
        RawLayer.embeddedJpeg =>
          service.requestEmbeddedJpeg(filePath, priority: priority),
        RawLayer.decoded => service.requestDecodedRawPreview(filePath,
            halfSize: halfSize, priority: priority),
      };
      _inFlightTasks[key] = task;
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
      _inFlightTasks.remove(key);
      completer.complete();
    }
  }
}
