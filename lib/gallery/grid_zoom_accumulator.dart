import 'dart:math' as math;

/// Scroll distance, in logical pixels, that changes the column count by one.
const double kGridZoomScrollStep = 20;

/// Pinch distance, in log scale units, that changes the column count by one.
const double kGridZoomLogScaleStep = 0.12;

/// How long a partial scroll gesture stays pending before it is discarded.
const Duration kGridZoomScrollResetDelay = Duration(milliseconds: 160);

/// Converts continuous zoom gestures into discrete column-count changes.
///
/// Both inputs are continuous while the column count is an integer, so the
/// leftover fraction of a gesture is carried until it accumulates into a whole
/// step. Without that carry, a slow trackpad pinch would never cross the
/// threshold and would register as no zoom at all.
///
/// This holds gesture state only. The caller owns the column count itself and
/// is responsible for clamping and persisting it.
class GridZoomAccumulator {
  double _scrollRemainder = 0;
  double _logScaleRemainder = 0;
  double _lastTrackpadScale = 1;

  /// Accumulates a mouse-wheel delta and returns the column-count change it
  /// completes, which is 0 until a full [kGridZoomScrollStep] accumulates.
  ///
  /// Scrolling down (positive delta) increases the column count.
  int addScrollDelta(double delta) {
    _scrollRemainder += delta;

    var columnChange = 0;
    while (_scrollRemainder.abs() >= kGridZoomScrollStep) {
      final direction = _scrollRemainder.isNegative ? -1 : 1;
      columnChange += direction;
      _scrollRemainder -= direction * kGridZoomScrollStep;
    }
    return columnChange;
  }

  /// Discards a partially accumulated scroll gesture.
  ///
  /// Called on a timer so an abandoned half-step does not combine with an
  /// unrelated scroll minutes later.
  void resetScroll() {
    _scrollRemainder = 0;
  }

  /// Begins a trackpad pinch, discarding any previous pinch state.
  void beginTrackpadPinch() {
    _lastTrackpadScale = 1;
    _logScaleRemainder = 0;
  }

  /// Accumulates a trackpad pinch update and returns the column-count change.
  ///
  /// Scale is accumulated in log space so that a pinch feels the same at every
  /// zoom level: multiplying the scale by a constant factor always advances the
  /// same distance, whereas a linear delta would step faster when zoomed in.
  ///
  /// Opening the pinch magnifies thumbnails, which means *fewer* columns, so
  /// the returned change is inverted relative to the scale direction.
  /// Non-positive and non-finite scales are ignored.
  int addTrackpadScale(double scale) {
    if (scale <= 0 || !scale.isFinite) {
      return 0;
    }

    final scaleChange = scale / _lastTrackpadScale;
    _lastTrackpadScale = scale;
    if (scaleChange <= 0 || !scaleChange.isFinite) {
      return 0;
    }

    _logScaleRemainder += math.log(scaleChange);
    var columnChange = 0;
    while (_logScaleRemainder.abs() >= kGridZoomLogScaleStep) {
      final direction = _logScaleRemainder.isNegative ? 1 : -1;
      columnChange += direction;
      _logScaleRemainder += direction * kGridZoomLogScaleStep;
    }
    return columnChange;
  }
}
