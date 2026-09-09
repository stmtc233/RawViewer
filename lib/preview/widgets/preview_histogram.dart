import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/app_theme.dart';
import '../image_histogram.dart';

class PreviewHistogram extends StatelessWidget {
  final HistogramSnapshot snapshot;

  const PreviewHistogram({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final data = snapshot.data;
    return Padding(
      key: const ValueKey('exif-histogram'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(l10n.exifHistogram,
                    style: const TextStyle(
                        fontSize: 11, color: RawViewerColors.mutedText))),
            const Text('RGB',
                style:
                    TextStyle(fontSize: 10, color: RawViewerColors.mutedText)),
          ]),
          const SizedBox(height: 6),
          SizedBox(
            height: 100,
            child: snapshot.isLoading
                ? const Center(
                    child: SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : data == null
                    ? Center(
                        child: Text(l10n.exifHistogramUnavailable,
                            style: const TextStyle(
                                fontSize: 11,
                                color: RawViewerColors.mutedText)))
                    : Semantics(
                        image: true,
                        label: l10n.exifHistogram,
                        child: RepaintBoundary(
                            child: CustomPaint(
                          painter: _HistogramPainter(data),
                          child: const SizedBox.expand(),
                        )),
                      ),
          ),
          const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0',
                    style: TextStyle(
                        fontSize: 10, color: RawViewerColors.mutedText)),
                Text('255',
                    style: TextStyle(
                        fontSize: 10, color: RawViewerColors.mutedText)),
              ]),
        ],
      ),
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final HistogramData data;
  _HistogramPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    canvas.drawRect(bounds, Paint()..color = RawViewerColors.canvas);
    final grid = Paint()
      ..color = RawViewerColors.border
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final x = i * size.width / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    final peak = [data.red, data.green, data.blue, data.luminance]
        .expand((bins) => bins)
        .fold<int>(0, math.max);
    if (peak > 0) {
      void draw(List<int> bins, Color color) {
        final line = Path();
        for (var i = 0; i < bins.length; i++) {
          final x = (i + 0.5) * size.width / bins.length;
          final y = size.height - 1 - bins[i] / peak * (size.height - 2);
          if (i == 0) {
            line.moveTo(x, y);
          } else {
            line.lineTo(x, y);
          }
        }
        final fill = Path.from(line)
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .18));
        canvas.drawPath(
            line,
            Paint()
              ..color = color.withValues(alpha: .8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1);
      }

      draw(data.luminance, RawViewerColors.text);
      draw(data.red, const Color(0xFFE57373));
      draw(data.green, const Color(0xFF81C784));
      draw(data.blue, const Color(0xFF64B5F6));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HistogramPainter oldDelegate) => oldDelegate.data != data;
}
