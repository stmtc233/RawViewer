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
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() {
      _isHovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _isHovered ? 1.0 : widget.restingOpacity;

    return Listener(
      behavior: widget.hitTestBehavior,
      onPointerDown: (event) {
        // Touch screens have no hover state, so reveal the controls on touch.
        if (event.kind != PointerDeviceKind.mouse &&
            event.kind != PointerDeviceKind.trackpad) {
          _setHovered(true);
        }
      },
      child: MouseRegion(
        opaque: false,
        hitTestBehavior: HitTestBehavior.translucent,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
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
