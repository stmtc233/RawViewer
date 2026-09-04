import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../preview_geometry.dart';

class PreviewOverviewMap extends StatelessWidget {
  final Widget image;
  final TransformationController transformationController;
  final Size viewportSize;

  const PreviewOverviewMap({
    super.key,
    required this.image,
    required this.transformationController,
    required this.viewportSize,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: kPreviewOverviewMapWidth,
        height: kPreviewOverviewMapHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RawViewerColors.surface.withValues(alpha: 0.78),
            border: Border.all(color: RawViewerColors.border),
            borderRadius: BorderRadius.circular(5),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 12, spreadRadius: 1),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final mapSize = Size(
                  constraints.maxWidth,
                  constraints.maxHeight,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    image,
                    AnimatedBuilder(
                      animation: transformationController,
                      builder: (context, child) {
                        final viewportRect = previewOverviewViewportRect(
                          transform: transformationController.value,
                          viewportSize: viewportSize,
                          mapSize: mapSize,
                        );
                        return CustomPaint(
                          painter: _PreviewOverviewViewportPainter(
                            viewportRect: viewportRect,
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewOverviewViewportPainter extends CustomPainter {
  final Rect viewportRect;

  const _PreviewOverviewViewportPainter({required this.viewportRect});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = RawViewerColors.accent.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = RawViewerColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(viewportRect, fillPaint);
    canvas.drawRect(viewportRect, strokePaint);
  }

  @override
  bool shouldRepaint(_PreviewOverviewViewportPainter oldDelegate) {
    return oldDelegate.viewportRect != viewportRect;
  }
}

