import 'preview_geometry.dart';

/// Turns a continuous stream of scroll signals into discrete navigation steps.
///
/// Trackpad scrolling does not always reach the app as pan/zoom gesture
/// events. A trackpad on the web, and a Windows trackpad whose driver cannot
/// feed DirectManipulation, reports one swipe as a flood of small mouse-wheel
/// signals instead. Acting on each of them steps through many images for a
/// single swipe, which is the over-sensitivity this class removes.
///
/// A gesture is credited with one step for its first signal and one more step
/// per [previewScrollGestureStepDistance] of further travel, so a light swipe
/// moves one image while a long swipe keeps advancing. Discrete mouse-wheel
/// notches arrive further apart than [previewScrollGestureGap] and therefore
/// keep their one-step-per-notch behaviour.
///
/// The preview page owns the instance rather than each page of the PageView:
/// a gesture that already triggered a switch must still be recognised as
/// continuing once the next page has moved under the pointer.
class ScrollGestureCoalescer {
  Duration? _lastSignalTime;
  double _remainder = 0;

  /// Records a scroll signal of [delta] and returns how many steps it adds.
  ///
  /// The result is signed like [delta] and is zero when the signal only
  /// extended the travel of a gesture that has already stepped.
  int addSignal(Duration timeStamp, double delta) {
    if (delta == 0) {
      return 0;
    }

    final Duration? previous = _lastSignalTime;
    _lastSignalTime = timeStamp;
    if (previous == null || timeStamp - previous >= previewScrollGestureGap) {
      _remainder = 0;
      return delta > 0 ? 1 : -1;
    }

    _remainder += delta;
    final int steps =
        (_remainder.abs() / previewScrollGestureStepDistance).floor();
    if (steps == 0) {
      return 0;
    }

    final int direction = _remainder.isNegative ? -1 : 1;
    _remainder -= direction * steps * previewScrollGestureStepDistance;
    return direction * steps;
  }
}
