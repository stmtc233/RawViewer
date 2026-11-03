import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../preview_geometry.dart';

/// One visibility state for every control floating over the preview.
///
/// The preview used to give each overlay its own hover reveal, so controls only
/// became clear one at a time and never left the photo. This controller is the
/// single answer to "is the chrome showing?": pointer activity reveals it, and
/// it hides itself once the pointer has been still for [idleDelay] — unless a
/// [PreviewChromeRegion] is holding it (the pointer is on a control) or
/// [canHide] says no (a menu or dialog is open over the preview).
///
/// With [autoHide] off the chrome is simply always visible.
class PreviewChromeController extends ChangeNotifier {
  PreviewChromeController({
    bool autoHide = true,
    this.idleDelay = previewChromeIdleHideDelay,
    this.canHide,
  }) : _autoHide = autoHide {
    _ensureTicker();
  }

  final Duration idleDelay;

  /// Consulted when the idle delay runs out. Returning false postpones hiding
  /// by another [idleDelay].
  final bool Function()? canHide;

  /// The idle delay is counted in ticks rather than by re-arming a timer on
  /// every pointer event: hover fires on every mouse move, and a tick counter
  /// makes that a single integer store.
  static const int _ticksPerDelay = 5;

  bool _autoHide;
  bool _revealed = true;
  int _holds = 0;
  int _idleTicks = 0;
  Timer? _ticker;
  final Set<int> _chromePointers = <int>{};
  bool _disposed = false;

  bool get autoHide => _autoHide;
  set autoHide(bool value) {
    if (_autoHide == value) return;
    _autoHide = value;
    _revealed = true;
    _idleTicks = 0;
    _ensureTicker();
    notifyListeners();
  }

  /// Whether controls should currently be painted and hit-testable.
  bool get visible => !_autoHide || _revealed;

  /// Whether a region is keeping the chrome on screen.
  bool get isHeld => _holds > 0;

  /// Shows the chrome and restarts the idle countdown.
  void reveal() {
    if (_disposed) return;
    _idleTicks = 0;
    if (!_revealed) {
      _revealed = true;
      notifyListeners();
    }
    _ensureTicker();
  }

  /// Hides the chrome now, unless something is holding it.
  void hide() {
    if (_disposed || !_autoHide || _holds > 0 || !_revealed) return;
    _stopTicker();
    _revealed = false;
    notifyListeners();
  }

  void toggle() => visible ? hide() : reveal();

  void hold() {
    _holds++;
    reveal();
  }

  void release() {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0) reveal();
  }

  /// Records that [pointer] went down on a control, so the preview does not
  /// treat the same tap as a tap on the photo.
  void markChromePointer(int pointer) => _chromePointers.add(pointer);

  /// Whether [pointer] went down on a control. Forgets the pointer.
  bool takeChromePointer(int pointer) => _chromePointers.remove(pointer);

  void _ensureTicker() {
    if (_disposed || !_autoHide || !_revealed) {
      _stopTicker();
      return;
    }
    _ticker ??= Timer.periodic(idleDelay ~/ _ticksPerDelay, (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    if (_disposed || !_autoHide || !_revealed) {
      _stopTicker();
      return;
    }
    if (_holds > 0) {
      _idleTicks = 0;
      return;
    }
    if (++_idleTicks < _ticksPerDelay) return;
    if (canHide?.call() == false) {
      _idleTicks = 0;
      return;
    }
    _stopTicker();
    _revealed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTicker();
    super.dispose();
  }
}

/// Provides a [PreviewChromeController] to the controls below it.
class PreviewChromeScope extends InheritedNotifier<PreviewChromeController> {
  const PreviewChromeScope({
    super.key,
    required PreviewChromeController controller,
    required super.child,
  }) : super(notifier: controller);

  static PreviewChromeController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PreviewChromeScope>()
      ?.notifier;
}

/// A control, or group of controls, that belongs to the preview chrome.
///
/// It fades out and stops taking input while the chrome is hidden, and while
/// the pointer is on it the chrome stays up. Without a [PreviewChromeScope]
/// above it, it is always visible.
///
/// With [fades] false the region still holds the chrome but is always painted:
/// for docked panels that reserve their own space and never cover the photo.
class PreviewChromeRegion extends StatefulWidget {
  const PreviewChromeRegion({
    super.key,
    required this.child,
    this.fades = true,
    this.hiddenOffset = Offset.zero,
    this.hitTestBehavior = HitTestBehavior.translucent,
  });

  final Widget child;
  final bool fades;

  /// Where the child slides to while hidden, as a fraction of its size.
  final Offset hiddenOffset;
  final HitTestBehavior hitTestBehavior;

  @override
  State<PreviewChromeRegion> createState() => _PreviewChromeRegionState();
}

class _PreviewChromeRegionState extends State<PreviewChromeRegion> {
  PreviewChromeController? _controller;
  bool _hovered = false;
  final Set<int> _pressedPointers = <int>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = PreviewChromeScope.maybeOf(context);
    if (!identical(controller, _controller)) {
      _releaseAll();
      _controller = controller;
    }
  }

  @override
  void dispose() {
    _releaseAll();
    super.dispose();
  }

  void _releaseAll() {
    final controller = _controller;
    if (controller == null) return;
    if (_hovered) controller.release();
    for (var i = 0; i < _pressedPointers.length; i++) {
      controller.release();
    }
    _hovered = false;
    _pressedPointers.clear();
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    _hovered = hovered;
    hovered ? _controller?.hold() : _controller?.release();
  }

  void _onPointerDown(PointerDownEvent event) {
    final controller = _controller;
    if (controller == null) return;
    controller.markChromePointer(event.pointer);
    if (_pressedPointers.add(event.pointer)) controller.hold();
  }

  void _onPointerEnd(PointerEvent event) {
    if (_pressedPointers.remove(event.pointer)) _controller?.release();
  }

  @override
  Widget build(BuildContext context) {
    final visible = !widget.fades || (_controller?.visible ?? true);
    Widget child = widget.child;
    if (widget.fades) {
      child = IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : widget.hiddenOffset,
          duration: previewChromeFadeDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: previewChromeFadeDuration,
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      );
    }
    return Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerEnd,
      onPointerCancel: _onPointerEnd,
      child: MouseRegion(
        // Opaque, deferring to the child: a control is hit only where it
        // paints, and a hit stops there. A non-opaque region reports a miss
        // even over its child, which would let the tap also reach the photo
        // beneath and wait out the photo's double-tap recognizer.
        hitTestBehavior: HitTestBehavior.deferToChild,
        // A hidden region does not hold the chrome: the pointer merely resting
        // where a control would be must not keep everything on screen.
        onEnter: (event) => _setHovered(visible),
        onHover: (_) {
          if (!_hovered && (_controller?.visible ?? true)) _setHovered(true);
        },
        onExit: (_) => _setHovered(false),
        child: child,
      ),
    );
  }
}

/// The plate behind a small group of floating preview controls.
///
/// Dark and borderless so it reads as part of the image surround rather than
/// as a window on top of the photo.
const BoxDecoration previewFloatingPanelDecoration = BoxDecoration(
  color: Color(0xC7101214),
  borderRadius: BorderRadius.all(Radius.circular(8)),
);

/// The plate behind the preview's top bar while it floats over the photo: a
/// scrim that darkens towards the edge instead of a solid bar with a border.
const BoxDecoration previewFloatingBarScrimDecoration = BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xB3000000), Color(0x66000000), Color(0x00000000)],
    stops: [0, 0.55, 1],
  ),
);

/// The plate behind the preview's top bar while it is docked above the photo.
const BoxDecoration previewDockedBarDecoration = BoxDecoration(
  color: RawViewerColors.surface,
  border: Border(bottom: BorderSide(color: RawViewerColors.mutedBorder)),
);

/// Text on a floating bar sits directly over the photo, so it carries its own
/// shadow instead of relying on the scrim alone.
const List<Shadow> previewFloatingTextShadows = [
  Shadow(color: Color(0x99000000), blurRadius: 6),
];
