import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../image_histogram.dart';

/// Observes the existing preview source without starting another RAW decode.
class HistogramImageObserver extends StatefulWidget {
  final ui.Image? image;
  final ImageProvider? provider;
  final ValueChanged<HistogramSnapshot> onChanged;

  const HistogramImageObserver({
    super.key,
    this.image,
    this.provider,
    required this.onChanged,
  }) : assert(image == null || provider == null);

  @override
  State<HistogramImageObserver> createState() => _HistogramImageObserverState();
}

class _HistogramImageObserverState extends State<HistogramImageObserver> {
  Timer? _timer;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _heldImage;
  int _generation = 0;
  int _analysisGeneration = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(HistogramImageObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.provider != widget.provider) {
      _schedule();
    }
  }

  void _releaseSource() {
    _timer?.cancel();
    if (_listener != null) _stream?.removeListener(_listener!);
    _listener = null;
    _stream = null;
    _heldImage?.dispose();
    _heldImage = null;
  }

  void _publish(HistogramSnapshot snapshot, int generation, {int? analysis}) {
    // Source changes can happen while the PageView is building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          generation == _generation &&
          (analysis == null || analysis == _analysisGeneration)) {
        widget.onChanged(snapshot);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _schedule() {
    final generation = ++_generation;
    _releaseSource();
    _heldImage = widget.image?.clone();
    _publish(const HistogramSnapshot.loading(), generation);
    _timer = Timer(const Duration(milliseconds: 150), () {
      final image = _heldImage;
      if (image != null) {
        unawaited(_analyze(image, generation));
      } else if (widget.provider case final provider?) {
        try {
          _stream = provider.resolve(createLocalImageConfiguration(context));
          _listener = ImageStreamListener((info, synchronousCall) {
            unawaited(_analyze(info.image, generation));
            info.dispose();
          }, onError: (Object error, StackTrace? stack) {
            _publish(const HistogramSnapshot.ready(null), generation);
          });
          _stream!.addListener(_listener!);
        } catch (_) {
          _publish(const HistogramSnapshot.ready(null), generation);
        }
      } else {
        _publish(const HistogramSnapshot.ready(null), generation);
      }
    });
  }

  Future<void> _analyze(ui.Image image, int generation) async {
    final analysis = ++_analysisGeneration;
    try {
      final data = await histogramForImage(image);
      if (!mounted || generation != _generation) return;
      _publish(HistogramSnapshot.ready(data), generation, analysis: analysis);
    } catch (_) {
      if (mounted) {
        _publish(const HistogramSnapshot.ready(null), generation,
            analysis: analysis);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    _releaseSource();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
