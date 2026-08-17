import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'native_lib.dart';

enum TaskPriority { high, low }

enum _RequestType { rawFastPreview, decodedRawPreview }

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

  final Queue<_WorkerRequest> _highPriorityQueue = Queue<_WorkerRequest>();
  final Queue<_WorkerRequest> _lowPriorityQueue = Queue<_WorkerRequest>();

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
    while (_idleWorkers.isNotEmpty &&
        (_highPriorityQueue.isNotEmpty || _lowPriorityQueue.isNotEmpty)) {
      final request = _highPriorityQueue.isNotEmpty
          ? _highPriorityQueue.removeFirst()
          : _lowPriorityQueue.removeFirst();

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

  // RAW fast preview layer: prefer embedded preview data and fall back to a
  // fast RAW-generated preview when the file has no embedded preview.
  WorkerTask<LibRawImage?> requestRawFastPreview(String path,
      {TaskPriority priority = TaskPriority.high}) {
    return WorkerTask._(
        this, _nextRequestId++, path, _RequestType.rawFastPreview,
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

    if (priority == TaskPriority.high) {
      _highPriorityQueue.addLast(request);
    } else {
      _lowPriorityQueue.addLast(request);
    }
    _drainQueues();

    return completer.future;
  }

  /// Re-prioritises a queued request. Requests already executing are left alone.
  void bumpRequest(int requestId, TaskPriority priority) {
    if (priority != TaskPriority.high) return;
    if (_requestToWorker.containsKey(requestId)) return;

    final index =
        _lowPriorityQueue.toList().indexWhere((r) => r.requestId == requestId);
    if (index == -1) return;

    final pending = _lowPriorityQueue.toList();
    final request = pending.removeAt(index);
    _lowPriorityQueue
      ..clear()
      ..addAll(pending);
    _highPriorityQueue.addLast(request);
    _drainQueues();
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

  bool _removeFromQueues(int requestId) {
    final before =
        _highPriorityQueue.length + _lowPriorityQueue.length;
    _highPriorityQueue.removeWhere((r) => r.requestId == requestId);
    _lowPriorityQueue.removeWhere((r) => r.requestId == requestId);
    return _highPriorityQueue.length + _lowPriorityQueue.length != before;
  }

  void dispose() {
    for (final isolate in _isolates) {
      isolate.kill(priority: Isolate.immediate);
    }
    _isolates.clear();
    _workerSendPorts.clear();
    _idleWorkers.clear();
    _requestToWorker.clear();
    _highPriorityQueue.clear();
    _lowPriorityQueue.clear();
    _pendingRequests.clear();
    _activeRequestsByKey.clear();
    _keyByRequestId.clear();
    _cancelledRequests.clear();
    _initFuture = null;
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
      final LibRawImage? result;
      if (message.type == _RequestType.rawFastPreview) {
        result = getRawFastPreviewSync(message.path, cancelToken: token);
      } else {
        result = getDecodedRawPreviewSync(message.path,
            halfSize: message.halfSize, cancelToken: token);
      }

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
