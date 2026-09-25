import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

/// Runs at most [maxConcurrent] async tasks at once; the rest wait their turn
/// in FIFO order.
///
/// Metadata reads each open a file and spawn a helper isolate. Letting every
/// visible grid tile, or every file in a sort, do that at once exhausts file
/// descriptors and spawns hundreds of isolates for no extra throughput.
class ConcurrencyLimiter {
  ConcurrencyLimiter(this.maxConcurrent) : assert(maxConcurrent > 0);

  final int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running < maxConcurrent) {
      _running++;
    } else {
      final slot = Completer<void>();
      _waiting.add(slot);
      // The finishing task hands its slot over, so _running stays counted.
      await slot.future;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }
}

/// Runs [action] over [items] with at most [concurrency] in flight.
///
/// Stops taking new items as soon as [isCancelled] returns true; actions
/// already started still run to completion.
Future<void> forEachConcurrently<T>(
  List<T> items,
  int concurrency,
  Future<void> Function(T item) action, {
  bool Function()? isCancelled,
}) async {
  var next = 0;
  Future<void> worker() async {
    while (next < items.length) {
      if (isCancelled?.call() ?? false) return;
      await action(items[next++]);
    }
  }

  await Future.wait([
    for (var i = 0; i < math.min(concurrency, items.length); i++) worker(),
  ]);
}
