import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/concurrency.dart';

void main() {
  test(
      'limiter caps concurrent tasks, runs waiters in order, and frees slots '
      'on failure', () async {
    final limiter = ConcurrencyLimiter(2);
    final gates = List.generate(5, (_) => Completer<void>());
    final started = <int>[];
    var running = 0;
    var peak = 0;

    Future<int> task(int index) => limiter.run(() async {
          started.add(index);
          running++;
          peak = running > peak ? running : peak;
          try {
            await gates[index].future;
            if (index == 0) throw StateError('failed');
            return index;
          } finally {
            running--;
          }
        });

    final results = [for (var i = 0; i < 5; i++) task(i)];
    final failure = expectLater(results[0], throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1]);

    gates[0].complete();
    await failure;
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);

    for (final gate in gates.skip(1)) {
      gate.complete();
    }
    expect(await Future.wait(results.skip(1)), [1, 2, 3, 4]);
    expect(started, [0, 1, 2, 3, 4]);
    expect(peak, 2);
  });

  test('forEachConcurrently stops taking items once cancelled', () async {
    final seen = <int>[];
    var cancelled = false;
    await forEachConcurrently(List.generate(20, (i) => i), 3, (item) async {
      seen.add(item);
      await Future<void>.delayed(Duration.zero);
      if (item == 4) cancelled = true;
    }, isCancelled: () => cancelled);
    expect(seen.length, lessThan(20));
    expect(seen, containsAll([0, 1, 2, 3, 4]));
  });
}
