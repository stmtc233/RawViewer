import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../preview_geometry.dart';

class PreviewHoverReveal extends StatefulWidget {
  final Widget child;
  final double restingOpacity;
  final HitTestBehavior hitTestBehavior;

  const PreviewHoverReveal({
    super.key,
    required this.child,
    required this.restingOpacity,
    this.hitTestBehavior = HitTestBehavior.translucent,
  });

  @override
  State<PreviewHoverReveal> createState() => _PreviewHoverRevealState();
}

class _PreviewHoverRevealState extends State<PreviewHoverReveal> {
  bool _isMouseHovered = false;
  bool _isTouchRevealed = false;
  final Set<int> _activeTouchPointers = <int>{};
  Timer? _touchHideTimer;

  static bool _isHoverCapable(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.mouse || kind == PointerDeviceKind.trackpad;

  @override
  void dispose() {
    _touchHideTimer?.cancel();
    super.dispose();
  }

  void _setMouseHovered(bool value) {
    if (_isMouseHovered == value) {
      return;
    }
    setState(() {
      _isMouseHovered = value;
    });
  }

  void _setTouchRevealed(bool value) {
    if (_isTouchRevealed == value || !mounted) {
      return;
    }
    setState(() {
      _isTouchRevealed = value;
    });
  }

  // Touch screens have no hover state: reveal on touch, then fade back to the
  // resting opacity a while after the last finger lifts, since no exit event
  // will ever arrive.
  void _handlePointerDown(PointerDownEvent event) {
    if (_isHoverCapable(event.kind)) {
      return;
    }
    _activeTouchPointers.add(event.pointer);
    _touchHideTimer?.cancel();
    _touchHideTimer = null;
    _setTouchRevealed(true);
  }

  void _handlePointerEnd(PointerEvent event) {
    if (!_activeTouchPointers.remove(event.pointer) ||
        _activeTouchPointers.isNotEmpty) {
      return;
    }
    _touchHideTimer?.cancel();
    _touchHideTimer = Timer(previewTouchRevealHoldDuration, () {
      _touchHideTimer = null;
      _setTouchRevealed(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _isMouseHovered || _isTouchRevealed;
    final opacity = revealed ? 1.0 : widget.restingOpacity;

    return Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerEnd,
      onPointerCancel: _handlePointerEnd,
      child: MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => _setMouseHovered(true),
        onExit: (_) => _setMouseHovered(false),
        child: AnimatedOpacity(
          opacity: opacity,
          duration: previewOverlayFadeDuration,
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
