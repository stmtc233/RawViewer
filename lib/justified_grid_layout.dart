import 'dart:math' as math;

/// A single row in a justified image grid.
///
/// Rows normally occupy the full available width. The item widths preserve
/// their source aspect ratios, so the images tile without unused cells.
class JustifiedGridRow {
  final List<int> indices;
  final List<double> widths;
  final double height;

  const JustifiedGridRow({
    required this.indices,
    required this.widths,
    required this.height,
  });
}

/// Splits image aspect ratios into rows that each fill [availableWidth].
///
/// [targetRowHeight] controls the intended density. The final row is justified
/// too unless that would exceed [maxFinalRowHeight]. In that case it keeps its
/// aspect ratios and leaves the remaining horizontal space unused.
List<JustifiedGridRow> buildJustifiedGridRows({
  required List<double> aspectRatios,
  required double availableWidth,
  required double targetRowHeight,
  double spacing = 0,
  double fallbackAspectRatio = 3 / 2,
  double? maxFinalRowHeight,
}) {
  if (aspectRatios.isEmpty || availableWidth <= 0 || targetRowHeight <= 0) {
    return const [];
  }

  final rows = <JustifiedGridRow>[];
  final targetAspectTotal = availableWidth / targetRowHeight;
  var index = 0;

  while (index < aspectRatios.length) {
    final indices = <int>[];
    final ratios = <double>[];
    var aspectTotal = 0.0;

    while (index < aspectRatios.length &&
        (ratios.isEmpty || aspectTotal < targetAspectTotal)) {
      final ratio = _normalizedAspectRatio(
        aspectRatios[index],
        fallbackAspectRatio,
      );
      indices.add(index);
      ratios.add(ratio);
      aspectTotal += ratio;
      index++;
    }

    final rowWidth =
        math.max(1.0, availableWidth - spacing * (ratios.length - 1));
    final justifiedRowHeight = rowWidth / aspectTotal;
    final isFinalRow = index == aspectRatios.length;
    final hasFinalRowHeightLimit = isFinalRow &&
        maxFinalRowHeight != null &&
        maxFinalRowHeight.isFinite &&
        maxFinalRowHeight > 0 &&
        justifiedRowHeight > maxFinalRowHeight;
    final rowHeight =
        hasFinalRowHeightLimit ? maxFinalRowHeight : justifiedRowHeight;
    final widths = <double>[];
    var occupiedWidth = 0.0;

    for (var itemIndex = 0; itemIndex < ratios.length; itemIndex++) {
      final isLastItem = itemIndex == ratios.length - 1;
      final width = !hasFinalRowHeightLimit && isLastItem
          ? availableWidth - occupiedWidth - spacing * itemIndex
          : ratios[itemIndex] * rowHeight;
      widths.add(math.max(0.0, width));
      occupiedWidth += width;
    }

    rows.add(
      JustifiedGridRow(indices: indices, widths: widths, height: rowHeight),
    );
  }

  return rows;
}

double _normalizedAspectRatio(double value, double fallback) {
  if (!value.isFinite || value <= 0) {
    return fallback;
  }
  return value.clamp(0.1, 10.0);
}
