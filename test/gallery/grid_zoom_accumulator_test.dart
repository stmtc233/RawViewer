import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/gallery/grid_zoom_accumulator.dart';

void main() {
  group('GridZoomAccumulator.addScrollDelta', () {
    test('returns 0 until a full step accumulates', () {
      final acc = GridZoomAccumulator();
      expect(acc.addScrollDelta(kGridZoomScrollStep - 1), 0);
    });

    test('returns 1 when exactly one step forward accumulates', () {
      final acc = GridZoomAccumulator();
      expect(acc.addScrollDelta(kGridZoomScrollStep), 1);
    });

    test('returns -1 when exactly one step backward accumulates', () {
      final acc = GridZoomAccumulator();
      expect(acc.addScrollDelta(-kGridZoomScrollStep), -1);
    });

    test('accumulates across calls and fires only on whole steps', () {
      final acc = GridZoomAccumulator();
      expect(acc.addScrollDelta(kGridZoomScrollStep * 0.6), 0);
      expect(acc.addScrollDelta(kGridZoomScrollStep * 0.6), 1);
    });

    test('returns multiple steps when delta is large', () {
      final acc = GridZoomAccumulator();
      expect(acc.addScrollDelta(kGridZoomScrollStep * 3), 3);
    });

    test('carries the leftover fraction into the next call', () {
      final acc = GridZoomAccumulator();
      acc.addScrollDelta(kGridZoomScrollStep * 1.5); // fires 1, carries 0.5
      expect(acc.addScrollDelta(kGridZoomScrollStep * 0.6), 1); // 0.5+0.6 >= 1
    });
  });

  group('GridZoomAccumulator.resetScroll', () {
    test('discards accumulated scroll so no step fires afterward', () {
      final acc = GridZoomAccumulator();
      acc.addScrollDelta(kGridZoomScrollStep * 0.8);
      acc.resetScroll();
      expect(acc.addScrollDelta(kGridZoomScrollStep * 0.3), 0);
    });
  });

  group('GridZoomAccumulator.addTrackpadScale', () {
    test('returns 0 for identity scale', () {
      final acc = GridZoomAccumulator()..beginTrackpadPinch();
      expect(acc.addTrackpadScale(1.0), 0);
    });

    test('returns 0 for non-positive scale', () {
      final acc = GridZoomAccumulator()..beginTrackpadPinch();
      expect(acc.addTrackpadScale(0.0), 0);
      expect(acc.addTrackpadScale(-1.0), 0);
    });

    test('returns -1 (fewer columns) when pinching open', () {
      // Opening the pinch makes thumbnails larger → fewer columns → negative
      final acc = GridZoomAccumulator()..beginTrackpadPinch();
      // Accumulate enough log-scale units in the positive direction for -1 step
      var change = 0;
      for (var i = 0; i < 30; i++) {
        change += acc.addTrackpadScale(1.0 + (i + 1) * 0.01);
      }
      expect(change, lessThan(0));
    });

    test('returns +1 (more columns) when pinching closed', () {
      // Closing the pinch makes thumbnails smaller → more columns → positive
      final acc = GridZoomAccumulator()..beginTrackpadPinch();
      var change = 0;
      for (var i = 0; i < 30; i++) {
        change += acc.addTrackpadScale(1.0 - (i + 1) * 0.01);
      }
      expect(change, greaterThan(0));
    });

    test('beginTrackpadPinch resets accumulated log scale', () {
      final acc = GridZoomAccumulator()..beginTrackpadPinch();
      // Accumulate almost a full step
      for (var i = 0; i < 10; i++) {
        acc.addTrackpadScale(1.0 + (i + 1) * 0.005);
      }
      acc.beginTrackpadPinch(); // reset
      // A fresh pinch from identity should still return 0 for a tiny delta
      expect(acc.addTrackpadScale(1.001), 0);
    });
  });
}
