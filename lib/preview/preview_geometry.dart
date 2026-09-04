import 'dart:math' as math;

import 'package:flutter/material.dart';

const Duration kImagePreviewOpenTransitionDuration =
    Duration(milliseconds: 100);
const Duration kImagePreviewCloseTransitionDuration =
    Duration(milliseconds: 80);
const double kImagePreviewToolbarHeight = 52;
const double kPreviewFilmstripHeight = 88;
const double kPreviewFilmstripItemWidth = 88;
const double kPreviewFilmstripItemExtent = 96;
const double kPreviewOverviewMapWidth = 180;
const double kPreviewOverviewMapHeight = 120;

const Duration kImagePreviewPageSwitchDuration = Duration(milliseconds: 55);
const Duration kImagePreviewRapidSwitchThreshold = Duration(milliseconds: 180);
const Duration kImagePreviewRapidSwitchSettleDelay =
    Duration(milliseconds: 140);

const double kMinPreviewScale = 0.25;
const double kMaxPreviewScale = 5.0;

// --- internal to preview ---
const double previewImageControlsHeight = 42;
const double previewOverviewGap = 10;
const double previewFilmstripScrollbarThickness = 2;
const double previewFilmstripScrollbarMainAxisMargin = 4;
const double previewFilmstripVisibilityEpsilon = 0.5;
const Duration previewOverlayFadeDuration = Duration(milliseconds: 140);
const double previewFitScale = 1.0;
const double previewScaleEpsilon = 0.01;
const double previewControlZoomStep = 1.25;
const Duration previewFitScaleLockDuration = Duration(milliseconds: 100);
const double previewTrackpadScaleSlop = 0.015;
const double trackpadPageDragSensitivity = 2.5;
const double trackpadFlingMinVelocity = 350;

double clampPreviewScale(double scale) {
  return scale.clamp(kMinPreviewScale, kMaxPreviewScale).toDouble();
}

/// Returns the small set of pages shown around the active image in the
/// preview filmstrip.
List<int> previewNavigationIndices({
  required int currentIndex,
  required int itemCount,
  int radius = 2,
}) {
  if (itemCount <= 0) {
    return const [];
  }

  final safeCurrentIndex = currentIndex.clamp(0, itemCount - 1).toInt();
  final safeRadius = radius < 0 ? 0 : radius;
  final first = math.max(0, safeCurrentIndex - safeRadius);
  final last = math.min(itemCount - 1, safeCurrentIndex + safeRadius);
  return [for (var index = first; index <= last; index++) index];
}

/// Maps the visible portion of the zoomed image onto an overview map.
Rect previewOverviewViewportRect({
  required Matrix4 transform,
  required Size viewportSize,
  required Size mapSize,
}) {
  if (viewportSize.isEmpty || mapSize.isEmpty) {
    return Offset.zero & mapSize;
  }

  final scale = transform.getMaxScaleOnAxis();
  if (!scale.isFinite || scale <= 0) {
    return Offset.zero & mapSize;
  }

  final translation = transform.getTranslation();
  final visibleWidth = viewportSize.width / scale;
  final visibleHeight = viewportSize.height / scale;
  final visibleLeft = (-translation.x / scale)
      .clamp(0.0, math.max(0.0, viewportSize.width - visibleWidth))
      .toDouble();
  final visibleTop = (-translation.y / scale)
      .clamp(0.0, math.max(0.0, viewportSize.height - visibleHeight))
      .toDouble();
  final visibleRight =
      (visibleLeft + visibleWidth).clamp(0.0, viewportSize.width).toDouble();
  final visibleBottom =
      (visibleTop + visibleHeight).clamp(0.0, viewportSize.height).toDouble();

  return Rect.fromLTRB(
    visibleLeft / viewportSize.width * mapSize.width,
    visibleTop / viewportSize.height * mapSize.height,
    visibleRight / viewportSize.width * mapSize.width,
    visibleBottom / viewportSize.height * mapSize.height,
  );
}

bool shouldResetPreviewPositionAtFitScale({
  required double currentScale,
  required double targetScale,
}) {
  return (currentScale > previewFitScale && targetScale <= previewFitScale) ||
      (currentScale < previewFitScale && targetScale >= previewFitScale);
}

enum PreviewScaleDirection { zoomIn, zoomOut }

/// Rotates an image view in clockwise 90-degree increments.
int rotateImageQuarterTurns(int currentQuarterTurns, int delta) {
  return (currentQuarterTurns + delta) % 4;
}
