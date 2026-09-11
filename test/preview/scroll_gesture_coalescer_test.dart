import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/preview/scroll_gesture_coalescer.dart';

/// A signal cadence like the one a Windows touchpad driver produces for one
/// swipe: many small deltas, one every frame or so.
Duration _burstTime(int index) => Duration(milliseconds: index * 10);

void main() {
  group('ScrollGestureCoalescer.addSignal', () {
    test('steps once for the first signal of a gesture', () {
      final coalescer = ScrollGestureCoalescer();
      expect(coalescer.addSignal(Duration.zero, 12), 1);
      expect(
        coalescer.addSignal(previewScrollGestureGap, -12),
        -1,
        reason: 'a new gesture steps in the direction it starts in',
      );
    });

    test('ignores a zero delta', () {
      final coalescer = ScrollGestureCoalescer();
      expect(coalescer.addSignal(Duration.zero, 0), 0);
    });

    test('collapses a flood of small signals into a single step', () {
      final coalescer = ScrollGestureCoalescer();
      var steps = 0;
      for (var i = 0; i < 8; i++) {
        steps += coalescer.addSignal(_burstTime(i), 12);
      }
      expect(steps, 1);
    });

    test('keeps stepping a long swipe proportionally', () {
      final coalescer = ScrollGestureCoalescer();
      var steps = 0;
      // 29 signals after the first: 348 logical pixels of further travel.
      for (var i = 0; i < 30; i++) {
        steps += coalescer.addSignal(_burstTime(i), 12);
      }
      expect(steps, 1 + (29 * 12 / previewScrollGestureStepDistance).floor());
    });

    test('gives every discrete wheel notch its own step', () {
      final coalescer = ScrollGestureCoalescer();
      var steps = 0;
      for (var i = 0; i < 3; i++) {
        steps += coalescer.addSignal(
          Duration(milliseconds: i * 200),
          previewScrollGestureStepDistance,
        );
      }
      expect(steps, 3);
    });

    test('keeps wheel speed when notches arrive faster than the gap', () {
      final coalescer = ScrollGestureCoalescer();
      var steps = 0;
      for (var i = 0; i < 3; i++) {
        steps += coalescer.addSignal(
          Duration(milliseconds: i * 30),
          previewScrollGestureStepDistance,
        );
      }
      expect(steps, 3);
    });

    test('treats a gap longer than the threshold as a new gesture', () {
      final coalescer = ScrollGestureCoalescer();
      expect(coalescer.addSignal(Duration.zero, 12), 1);
      expect(coalescer.addSignal(Duration.zero, 12), 0);
      expect(
        coalescer.addSignal(previewScrollGestureGap, 12),
        1,
        reason: 'the new gesture is not held back by the previous remainder',
      );
    });

    test('a reversal inside one gesture cancels its travel', () {
      final coalescer = ScrollGestureCoalescer();
      expect(coalescer.addSignal(Duration.zero, 90), 1);
      expect(coalescer.addSignal(Duration(milliseconds: 10), -180), -1);
    });
  });
}
