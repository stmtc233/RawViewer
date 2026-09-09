import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

class HistogramSnapshot {
  final HistogramData? data;
  final bool isLoading;

  const HistogramSnapshot.loading()
      : data = null,
        isLoading = true;
  const HistogramSnapshot.ready(this.data) : isLoading = false;
}

class HistogramData {
  final List<int> red;
  final List<int> green;
  final List<int> blue;
  final List<int> luminance;

  const HistogramData(this.red, this.green, this.blue, this.luminance);
}

/// Counts SDR display values, not linear sensor data or native HDR output.
HistogramData? histogramFromRgba(Uint8List bytes) {
  if (bytes.length % 4 != 0) {
    throw ArgumentError('Expected packed RGBA pixels');
  }
  final red = List<int>.filled(256, 0);
  final green = List<int>.filled(256, 0);
  final blue = List<int>.filled(256, 0);
  final luminance = List<int>.filled(256, 0);
  var samples = 0;
  for (var i = 0; i < bytes.length; i += 4) {
    if (bytes[i + 3] == 0) continue;
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    red[r]++;
    green[g]++;
    blue[b]++;
    luminance[((r * 2126 + g * 7152 + b * 722) / 10000).round()]++;
    samples++;
  }
  return samples == 0 ? null : HistogramData(red, green, blue, luminance);
}

/// Borrows [image]; the clone keeps it alive across readback and navigation.
Future<HistogramData?> histogramForImage(ui.Image image) async {
  final source = image.clone();
  ui.Image? sample;
  try {
    const maxDimension = 512;
    final scale =
        math.min(1.0, maxDimension / math.max(source.width, source.height));
    final width = math.max(1, (source.width * scale).round());
    final height = math.max(1, (source.height * scale).round());
    if (scale < 1) {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawImageRect(
        source,
        ui.Rect.fromLTWH(
            0, 0, source.width.toDouble(), source.height.toDouble()),
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.low,
      );
      final picture = recorder.endRecording();
      try {
        sample = await picture.toImage(width, height);
      } finally {
        picture.dispose();
      }
    }
    final bytes = await (sample ?? source)
        .toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (bytes == null) return null;
    return await compute(histogramFromRgba,
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
  } finally {
    sample?.dispose();
    source.dispose();
  }
}
