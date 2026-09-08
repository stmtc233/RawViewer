import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Native surfaces preserve gain maps and extended luminance outside Flutter's
/// SDR texture pipeline. Unsupported displays retain the bitmap underneath.
class HdrImage extends StatefulWidget {
  final String filePath;
  final int decodeWidth;
  final VoidCallback? onHdrDetected;

  const HdrImage({
    super.key,
    required this.filePath,
    required this.decodeWidth,
    this.onHdrDetected,
  });

  @override
  State<HdrImage> createState() => _HdrImageState();
}

class _HdrImageState extends State<HdrImage> {
  bool _supported = false;
  bool _failed = false;
  bool _reportedHdr = false;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    if (![TargetPlatform.macOS, TargetPlatform.iOS, TargetPlatform.android]
        .contains(defaultTargetPlatform)) {
      return;
    }
    try {
      final supported = await const MethodChannel('rawviewer/hdr')
              .invokeMethod<bool>('isSupported') ??
          false;
      if (mounted) setState(() => _supported = supported);
    } on PlatformException {
      // Native HDR is optional; the SDR image remains available.
    } on MissingPluginException {
      // Also covers tests and runners without the HDR integration.
    }
  }

  Future<void> _load(int id) async {
    try {
      final loaded =
          await MethodChannel('rawviewer/hdr/$id').invokeMethod<bool>('load', {
                'path': widget.filePath,
                'width': widget.decodeWidth,
              }) ??
              false;
      if (!mounted) return;
      if (loaded && !_reportedHdr) {
        _reportedHdr = true;
        widget.onHdrDetected?.call();
      }
      if (!loaded) setState(() => _failed = true);
    } on PlatformException {
      if (mounted) setState(() => _failed = true);
    } on MissingPluginException {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _failed) return const SizedBox.shrink();
    const viewType = 'rawviewer/hdr_image';
    const gestures = <Factory<OneSequenceGestureRecognizer>>{};
    final Widget view;
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        view = AppKitView(
            viewType: viewType,
            onPlatformViewCreated: _load,
            gestureRecognizers: gestures);
      case TargetPlatform.iOS:
        view = UiKitView(
            viewType: viewType,
            onPlatformViewCreated: _load,
            gestureRecognizers: gestures);
      case TargetPlatform.android:
        // Hybrid composition is required: an SDR Flutter texture would clip HDR.
        view = PlatformViewLink(
          viewType: viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: gestures,
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          ),
          onCreatePlatformView: (params) {
            final controller = PlatformViewsService.initExpensiveAndroidView(
              id: params.id,
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
            );
            controller
                .addOnPlatformViewCreatedListener(params.onPlatformViewCreated);
            controller.addOnPlatformViewCreatedListener(_load);
            controller.create();
            return controller;
          },
        );
      default:
        return const SizedBox.shrink();
    }
    return IgnorePointer(child: view);
  }
}
