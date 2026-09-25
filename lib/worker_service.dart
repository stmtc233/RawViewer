import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'native_lib.dart';

enum TaskPriority { high, low }

enum _RequestType { rawThumbnail, embeddedJpeg, decodedRawPreview }

/// Decodes RAW previews on a pool of isolates.
///
/// Work is handed out from a single shared queue to whichever isolate is idle,
/// rather than round-robin. A slow full-size decode therefore cannot block
/// unrelated requests that happened to hash to the same worker.
class WorkerService {
  static final WorkerService _instance = WorkerService._internal();
  factory WorkerService() => _instance;

  WorkerService._internal();

  // Each decode is itself multi-threaded where OpenMP is enabled, so a very
  // large pool would just oversubscribe the CPU.
  static final int _poolSize = Platform.numberOfProcessors.clamp(2, 6);

  final List<SendPort> _workerSendPorts = [];
  final List<Isolate> _isolates = [];
  final Set<int> _idleWorkers = {};

  /// Which worker is currently executing a given request, so cancellation can
  /// be routed to the isolate that can actually abort it.
  final Map<int, int> _requestToWorker = {};

  final WorkerRequestQueue<_WorkerRequest> _queue =
      WorkerRequestQueue<_WorkerRequest>();

  final Map<int, Completer<LibRawImage?>> _pendingRequests = {};
  int _nextRequestId = 0;

  // Deduplication, kept in both directions so responses do not need a scan.
  final Map<String, int> _activeRequestsByKey = {};
  final Map<int, String> _keyByRequestId = {};

  final Set<int> _cancelledRequests = {};

  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    for (int i = 0; i < _poolSize; i++) {
      final workerIndex = i;
      final handshakePort = ReceivePort();
      final isolate = await Isolate.spawn(_workerEntry, handshakePort.sendPort);
      final sendPort = await handshakePort.first as SendPort;
      handshakePort.close();

      final responsePort = ReceivePort();
      sendPort.send(responsePort.sendPort);
      responsePort.listen((message) => _handleResponse(workerIndex, message));

      _isolates.add(isolate);
      _workerSendPorts.add(sendPort);
      _idleWorkers.add(workerIndex);
    }
  }

  void _handleResponse(int workerIndex, dynamic message) {
    if (message is! _WorkerResponse) return;

    final requestId = message.requestId;
    _requestToWorker.remove(requestId);
    _idleWorkers.add(workerIndex);

    final completer = _pendingRequests.remove(requestId);
    final key = _keyByRequestId.remove(requestId);
    if (key != null && _activeRequestsByKey[key] == requestId) {
      _activeRequestsByKey.remove(key);
    }

    if (completer != null && !completer.isCompleted) {
      if (_cancelledRequests.remove(requestId)) {
        completer.complete(null);
      } else if (message.error != null) {
        completer.completeError(message.error!);
      } else {
        completer.complete(message.image);
      }
    } else {
      _cancelledRequests.remove(requestId);
    }

    _drainQueues();
  }

  /// Hands queued work to idle workers, highest priority first.
  void _drainQueues() {
    while (_idleWorkers.isNotEmpty && _queue.isNotEmpty) {
      final request = _queue.removeNext();

      if (_cancelledRequests.contains(request.requestId)) {
        _finalizeCancelled(request.requestId);
        continue;
      }

      final workerIndex = _idleWorkers.first;
      _idleWorkers.remove(workerIndex);
      _requestToWorker[request.requestId] = workerIndex;
      _workerSendPorts[workerIndex].send(request);
    }
  }

  void _finalizeCancelled(int requestId) {
    _cancelledRequests.remove(requestId);
    final completer = _pendingRequests.remove(requestId);
    final key = _keyByRequestId.remove(requestId);
    if (key != null && _activeRequestsByKey[key] == requestId) {
      _activeRequestsByKey.remove(key);
    }
    if (completer != null && !completer.isCompleted) {
      completer.complete(null);
    }
  }

  // RAW thumbnail layer: the cheapest image LibRaw can produce — embedded
  // preview data when present, a half-size RAW decode otherwise.
  WorkerTask<LibRawImage?> requestRawThumbnail(String path,
      {TaskPriority priority = TaskPriority.high}) {
    return WorkerTask._(this, _nextRequestId++, path, _RequestType.rawThumbnail,
        priority: priority);
  }

  // The JPEG embedded in the RAW container, with no fallback: a null result
  // means this file carries no embedded JPEG.
  WorkerTask<LibRawImage?> requestEmbeddedJpeg(String path,
      {TaskPriority priority = TaskPriority.high}) {
    return WorkerTask._(this, _nextRequestId++, path, _RequestType.embeddedJpeg,
        priority: priority);
  }

  // Decoded RAW layer used as the final high-quality image.
  WorkerTask<LibRawImage?> requestDecodedRawPreview(String path,
      {int halfSize = 1, TaskPriority priority = TaskPriority.high}) {
    return WorkerTask._(
        this, _nextRequestId++, path, _RequestType.decodedRawPreview,
        halfSize: halfSize, priority: priority);
  }

  Future<LibRawImage?> _executeTask(
      int requestId, String path, _RequestType type,
      {int halfSize = 1, TaskPriority priority = TaskPriority.high}) async {
    await init();

    if (_cancelledRequests.contains(requestId)) {
      _cancelledRequests.remove(requestId);
      return null;
    }

    final dedupeKey = '$path:${type.name}:$halfSize';
    final existingReqId = _activeRequestsByKey[dedupeKey];
    if (existingReqId != null) {
      final existing = _pendingRequests[existingReqId];
      if (existing != null && !existing.isCompleted) {
        bumpRequest(existingReqId, priority);
        return existing.future;
      }
      // Stale entry from a finished or cancelled request; drop it and dispatch
      // normally instead of falling through and duplicating the decode.
      _activeRequestsByKey.remove(dedupeKey);
      _keyByRequestId.remove(existingReqId);
    }

    final completer = Completer<LibRawImage?>();
    _pendingRequests[requestId] = completer;
    _activeRequestsByKey[dedupeKey] = requestId;
    _keyByRequestId[requestId] = dedupeKey;

    final request = _WorkerRequest(
      requestId: requestId,
      path: path,
      type: type,
      halfSize: halfSize,
      priority: priority,
    );

    _queue.add(requestId, request, priority);
    _drainQueues();

    return completer.future;
  }

  /// Re-prioritises a queued request. Requests already executing are left alone.
  void bumpRequest(int requestId, TaskPriority priority) {
    if (priority != TaskPriority.high) return;
    if (_requestToWorker.containsKey(requestId)) return;
    if (_queue.promote(requestId)) _drainQueues();
  }

  /// Moves a queued high-priority request to the back of the low queue.
  ///
  /// Unlike [cancelRequest] the decode still runs and still delivers its
  /// result, so this is safe for requests shared through deduplication. It
  /// lets work that is still wanted run first. Requests already executing, or
  /// not queued yet, are left alone.
  void demoteRequest(int requestId) {
    if (_requestToWorker.containsKey(requestId)) return;
    _queue.demote(requestId);
  }

  void cancelRequest(int requestId) {
    _cancelledRequests.add(requestId);

    // Still queued: drop it without ever starting the decode.
    if (_removeFromQueues(requestId)) {
      _finalizeCancelled(requestId);
      _drainQueues();
      return;
    }

    // Already running: tell that worker to trip the native cancel token so
    // LibRaw aborts instead of decoding an image nobody is waiting for.
    final workerIndex = _requestToWorker[requestId];
    if (workerIndex != null) {
      _workerSendPorts[workerIndex].send(_CancelRequest(requestId));
    }

    final completer = _pendingRequests[requestId];
    if (completer != null && !completer.isCompleted) {
      // Unblock the caller now; the worker's late response is discarded.
      _pendingRequests.remove(requestId);
      completer.complete(null);
    }
  }

  bool _removeFromQueues(int requestId) => _queue.remove(requestId);

  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _workerSendPorts.clear();
    _idleWorkers.clear();
    _requestToWorker.clear();
    _queue.clear();
    _pendingRequests.clear();
    _activeRequestsByKey.clear();
    _keyByRequestId.clear();
    _cancelledRequests.clear();
    _initFuture = null;
  }
}

/// The two-level queue behind [WorkerService]: every high-priority request
/// runs before any low-priority one, and each level is FIFO.
///
/// Kept apart from the isolate plumbing so the ordering rules can be tested
/// directly.
class WorkerRequestQueue<T> {
  final Queue<(int, T)> _high = Queue<(int, T)>();
  final Queue<(int, T)> _low = Queue<(int, T)>();

  bool get isEmpty => _high.isEmpty && _low.isEmpty;
  bool get isNotEmpty => !isEmpty;

  void add(int id, T request, TaskPriority priority) =>
      (priority == TaskPriority.high ? _high : _low).addLast((id, request));

  /// Removes and returns the next request to run. The queue must not be empty.
  T removeNext() => (_high.isNotEmpty ? _high : _low).removeFirst().$2;

  /// Moves a queued low-priority request to the back of the high queue.
  bool promote(int id) => _move(id, from: _low, to: _high);

  /// Moves a queued high-priority request to the back of the low queue.
  bool demote(int id) => _move(id, from: _high, to: _low);

  /// Drops a queued request. Returns whether it was queued.
  bool remove(int id) {
    final before = _high.length + _low.length;
    _high.removeWhere((entry) => entry.$1 == id);
    _low.removeWhere((entry) => entry.$1 == id);
    return _high.length + _low.length != before;
  }

  void clear() {
    _high.clear();
    _low.clear();
  }

  bool _move(
    int id, {
    required Queue<(int, T)> from,
    required Queue<(int, T)> to,
  }) {
    (int, T)? found;
    from.removeWhere((entry) {
      if (found != null || entry.$1 != id) return false;
      found = entry;
      return true;
    });
    if (found == null) return false;
    to.addLast(found!);
    return true;
  }
}

class WorkerTask<T> {
  final WorkerService _service;
  final int requestId;
  final String path;
  final _RequestType _type;
  final int halfSize;
  final TaskPriority priority;

  Future<T>? _result;

  WorkerTask._(this._service, this.requestId, this.path, this._type,
      {this.halfSize = 1, this.priority = TaskPriority.high});

  /// The decode result. Awaiting more than once reuses the same in-flight
  /// request instead of dispatching the work again.
  Future<T> get result => _result ??= _service
      ._executeTask(requestId, path, _type,
          halfSize: halfSize, priority: priority)
      .then((image) => image as T);

  void cancel() {
    _service.cancelRequest(requestId);
  }
}

class _WorkerRequest {
  final int requestId;
  final String path;
  final _RequestType type;
  final int halfSize;
  final TaskPriority priority;

  _WorkerRequest({
    required this.requestId,
    required this.path,
    required this.type,
    this.halfSize = 1,
    this.priority = TaskPriority.high,
  });
}

class _CancelRequest {
  final int requestId;
  _CancelRequest(this.requestId);
}

class _WorkerResponse {
  final int requestId;
  final LibRawImage? image;
  final String? error;

  _WorkerResponse({
    required this.requestId,
    this.image,
    this.error,
  });
}

void _workerEntry(SendPort mainSendPort) {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  SendPort? replyPort;

  // Cancel tokens for requests currently being decoded by this isolate. The
  // native side polls these from LibRaw's progress callback.
  final Map<int, RawCancelToken> activeTokens = {};

  // Cancellations that arrived before the request started running here.
  final Set<int> preCancelled = {};

  receivePort.listen((message) async {
    if (message is SendPort) {
      replyPort = message;
      return;
    }

    if (message is _CancelRequest) {
      final token = activeTokens[message.requestId];
      if (token != null) {
        token.cancel();
      } else {
        preCancelled.add(message.requestId);
      }
      return;
    }

    if (message is! _WorkerRequest) return;

    final port = replyPort;
    if (port == null) return;

    final token = RawCancelToken();
    if (preCancelled.remove(message.requestId)) {
      token.cancel();
    }
    activeTokens[message.requestId] = token;

    try {
      // The embedded-JPEG extraction ABI takes no cancel token: it is a
      // container read with no demosaic, so there is nothing worth aborting.
      final result = switch (message.type) {
        _RequestType.rawThumbnail =>
          getRawThumbnailSync(message.path, cancelToken: token),
        _RequestType.embeddedJpeg => getEmbeddedJpegImageSync(message.path),
        _RequestType.decodedRawPreview => getDecodedRawPreviewSync(message.path,
            halfSize: message.halfSize, cancelToken: token),
      };

      port.send(_WorkerResponse(requestId: message.requestId, image: result));
    } catch (e) {
      port.send(
          _WorkerResponse(requestId: message.requestId, error: e.toString()));
    } finally {
      activeTokens.remove(message.requestId);
      // Safe only after the native call has returned.
      token.dispose();
    }
  });
}
