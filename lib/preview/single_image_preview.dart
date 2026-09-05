import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/decode_target.dart';
import '../core/pointer_modifiers.dart';
import '../core/raw_view_mode.dart';
import '../image_store.dart';
import '../l10n/app_localizations.dart';
import '../media_group.dart';
import '../settings_page.dart';
import '../native_lib.dart';
import '../ui/app_theme.dart';
import '../ui/desktop_controls.dart';
import '../ui/raw_image_widget.dart';
import '../viewer_image.dart';
import '../worker_service.dart';
import 'preview_geometry.dart';
import 'widgets/preview_hover_reveal.dart';
import 'widgets/preview_overview_map.dart';

class SingleImagePreview extends StatefulWidget {
  final MediaGroup mediaGroup;
  final int thumbnailResizeWidth;
  final int previewThumbnailResizeWidth;
  final ImageStore imageStore;
  final ViewerSettings settings;
  final int rotationQuarterTurns;
  final RawViewMode viewMode;
  final ValueChanged<int> onRotationRequested;
  final VoidCallback onResetRotationRequested;
  final ValueChanged<int> onSwitchRequest;
  final ValueChanged<PointerPanZoomStartEvent> onTrackpadPanStart;
  final ValueChanged<PointerPanZoomUpdateEvent> onTrackpadPanUpdate;
  final ValueChanged<PointerPanZoomEndEvent> onTrackpadPanEnd;
  final VoidCallback onTrackpadPanCancel;
  final bool isActive;
  final bool showPreviewOverview;
  final double overviewBottomInset;
  final ValueNotifier<bool> isFastScrolling;
  final ValueChanged<bool>? onScaleStateChanged;

  /// Reports whether this RAW turned out to carry an embedded JPEG, so the
  /// preview's mode switch can grey out that option.
  final ValueChanged<bool>? onEmbeddedJpegAvailability;

  const SingleImagePreview({
    super.key,
    required this.mediaGroup,
    required this.thumbnailResizeWidth,
    required this.previewThumbnailResizeWidth,
    required this.imageStore,
    required this.settings,
    required this.rotationQuarterTurns,
    required this.viewMode,
    required this.onRotationRequested,
    required this.onResetRotationRequested,
    required this.onSwitchRequest,
    required this.onTrackpadPanStart,
    required this.onTrackpadPanUpdate,
    required this.onTrackpadPanEnd,
    required this.onTrackpadPanCancel,
    required this.isActive,
    required this.showPreviewOverview,
    required this.overviewBottomInset,
    required this.isFastScrolling,
    this.onScaleStateChanged,
    this.onEmbeddedJpegAvailability,
  });

  String get filePath => mediaGroup.primary.path;
  bool get isRaw => mediaGroup.isRaw;
  bool get hasPairedJpeg => mediaGroup.hasPairedJpeg;

  @override
  State<SingleImagePreview> createState() => _SingleImagePreviewState();
}

class _SingleImagePreviewState extends State<SingleImagePreview> {
  /// A cached thumbnail-layer image, peeked synchronously so the first frame of
  /// a page switch is never blank. Soft, and only ever a stand-in.
  ViewerImage? _thumbnailImage;

  /// The RAW's embedded JPEG. Both a display mode of its own and the interim
  /// sharp image while a decode runs.
  ViewerImage? _embeddedJpegImage;
  ViewerImage? _decodedRawPreviewImage;

  bool _embeddedJpegRequested = false;
  bool _isLoadingDecodedRawPreview = false;

  /// Captured once, on purpose: this doubles as part of the decode cache key,
  /// so changing it mid-page would strand the image already on screen under a
  /// key nothing asks for again. A new value takes effect on the next preview.
  late int _rawDecodeHalfSize;
  final TransformationController _transformationController =
      TransformationController();
  bool _panEnabled = false;
  bool _isZoomed = false;
  // Mouse-wheel zoom is explicit so it does not conflict with navigation.
  // Touch keeps InteractiveViewer's pinch flow, while trackpad pinch is
  // handled from raw pan/zoom updates.
  bool _scaleEnabled = false;
  final Set<int> _activePointers = {};
  double _lastTrackpadScale = 1;
  bool _isTrackpadScaling = false;
  bool _isTrackpadPageDrag = false;
  Timer? _fitScaleLockTimer;
  bool _isFitScaleLocked = false;
  PreviewScaleDirection? _fitScaleLockDirection;

  /// Only the expensive decoded-RAW task is tracked for cancellation.
  ///
  /// The thumbnail and embedded-JPEG layers are deliberately never cancelled:
  /// they are cheap, and the worker dedupes them by path, so cancelling ours
  /// would also resolve a grid tile's shared request to null and leave that
  /// tile showing a broken image.
  WorkerTask<LibRawImage?>? _decodedRawTask;

  bool get _isShowingPairedJpeg => widget.viewMode == RawViewMode.pairedJpeg;
  bool get _isShowingEmbeddedJpeg =>
      widget.viewMode == RawViewMode.embeddedJpeg;

  @override
  void initState() {
    super.initState();
    _rawDecodeHalfSize = widget.settings.useHalfSizeRawDecode ? 1 : 0;

    // Take a cached thumbnail-layer image synchronously so the first frame of a
    // page switch already paints something instead of an empty preview area.
    // It is soft, but soft beats black, and it is replaced as soon as the real
    // layer for this view mode arrives.
    if (widget.isRaw) {
      _thumbnailImage = widget.imageStore.peek(
            widget.filePath,
            RawLayer.thumbnail,
            targetWidth: widget.thumbnailResizeWidth,
          ) ??
          widget.imageStore.peek(
            widget.filePath,
            RawLayer.thumbnail,
            targetWidth: widget.previewThumbnailResizeWidth,
          );
    }

    unawaited(_loadRawDisplayLayers());
    _transformationController.addListener(_onTransformationChange);
    widget.isFastScrolling.addListener(_onFastScrollingChanged);
  }

  @override
  void didUpdateWidget(SingleImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.isFastScrolling != widget.isFastScrolling) {
      oldWidget.isFastScrolling.removeListener(_onFastScrollingChanged);
      widget.isFastScrolling.addListener(_onFastScrollingChanged);
    }

    if (!widget.isActive && oldWidget.isActive) {
      _clearFitScaleLock();
      _transformationController.value = Matrix4.identity();
      _cancelDecodedRawTask();
    }

    if (widget.rotationQuarterTurns != oldWidget.rotationQuarterTurns) {
      _clearFitScaleLock();
      _transformationController.value = Matrix4.identity();
    }

    if (widget.viewMode != oldWidget.viewMode) {
      if (widget.viewMode != RawViewMode.decodedRaw) {
        _decodedRawTask?.cancel();
        _decodedRawTask = null;
        _isLoadingDecodedRawPreview = false;
      }
      // The embedded JPEG serves both its own mode and the interim image while
      // a decode runs, so a mode change may need a layer that was never asked
      // for yet.
      unawaited(_loadRawDisplayLayers());
    }

    if (widget.isActive && !oldWidget.isActive) {
      // Reload skips whatever layer is already available.
      unawaited(_loadRawDisplayLayers());
    }
  }

  @override
  void dispose() {
    widget.isFastScrolling.removeListener(_onFastScrollingChanged);
    _clearFitScaleLock();
    _decodedRawTask?.cancel();
    _thumbnailImage?.dispose();
    _embeddedJpegImage?.dispose();
    _decodedRawPreviewImage?.dispose();
    _transformationController.removeListener(_onTransformationChange);
    _transformationController.dispose();
    super.dispose();
  }

  void _cancelDecodedRawTask() {
    _decodedRawTask?.cancel();
    _decodedRawTask = null;
    if (_isLoadingDecodedRawPreview && mounted) {
      setState(() {
        _isLoadingDecodedRawPreview = false;
      });
    } else {
      _isLoadingDecodedRawPreview = false;
    }
  }

  void _onFastScrollingChanged() {
    if (!widget.isActive) return;

    if (widget.isFastScrolling.value) {
      // Do not spend CPU on a full decode the user is scrolling straight past.
      _cancelDecodedRawTask();
    } else {
      unawaited(_loadRawDisplayLayers());
    }
  }

  void _onTransformationChange() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final newPanEnabled =
        (scale - previewFitScale).abs() > previewScaleEpsilon;
    if (_panEnabled != newPanEnabled || _isZoomed != newPanEnabled) {
      setState(() {
        _panEnabled = newPanEnabled;
        _isZoomed = newPanEnabled;
      });
    }
  }

  void _lockAtFitScale(PreviewScaleDirection direction) {
    _isFitScaleLocked = true;
    _fitScaleLockDirection = direction;
    _fitScaleLockTimer?.cancel();
    _fitScaleLockTimer = Timer(previewFitScaleLockDuration, () {
      _fitScaleLockTimer = null;
      _isFitScaleLocked = false;
      _fitScaleLockDirection = null;
    });
  }

  void _clearFitScaleLock() {
    _fitScaleLockTimer?.cancel();
    _fitScaleLockTimer = null;
    _isFitScaleLocked = false;
    _fitScaleLockDirection = null;
  }

  Future<void> _loadRawDisplayLayers() async {
    // Bitmap files and the paired-JPEG mode rely entirely on Flutter's own
    // file/image pipeline.
    if (!widget.isRaw || !widget.isActive || _isShowingPairedJpeg) return;

    // The embedded JPEG is wanted in both RAW modes: as the image itself in
    // embedded mode, and as the interim sharp image while a decode runs. It is
    // also the probe that tells the mode switch whether this file has one.
    await _loadEmbeddedJpeg();

    if (!widget.isActive || widget.isFastScrolling.value) return;
    if (_isShowingEmbeddedJpeg && _embeddedJpegImage != null) return;
    if (_isShowingPairedJpeg) return;
    if (_decodedRawPreviewImage != null) return;

    setState(() {
      _isLoadingDecodedRawPreview = true;
    });

    final decodedRawPreviewImage = await widget.imageStore.load(
      widget.filePath,
      RawLayer.decoded,
      halfSize: _rawDecodeHalfSize,
      onTaskStarted: (task) => _decodedRawTask = task,
    );
    _decodedRawTask = null;

    // A cancelled or superseded load must not overwrite what is on screen.
    if (!mounted ||
        !widget.isActive ||
        _isShowingPairedJpeg ||
        (_isShowingEmbeddedJpeg && _embeddedJpegImage != null)) {
      decodedRawPreviewImage?.dispose();
      if (mounted && _isLoadingDecodedRawPreview) {
        setState(() {
          _isLoadingDecodedRawPreview = false;
        });
      }
      return;
    }

    setState(() {
      if (decodedRawPreviewImage != null) {
        _decodedRawPreviewImage?.dispose();
        _decodedRawPreviewImage = decodedRawPreviewImage;
      }
      _isLoadingDecodedRawPreview = false;
    });
  }

  /// Loads the embedded JPEG once per file and reports whether it exists.
  ///
  /// No `targetWidth`: this is a full-screen layer, so it keeps the embedded
  /// JPEG's own resolution rather than the grid's thumbnail size.
  Future<void> _loadEmbeddedJpeg() async {
    if (_embeddedJpegRequested) return;
    _embeddedJpegRequested = true;

    final priority =
        widget.isFastScrolling.value ? TaskPriority.low : TaskPriority.high;
    final image = await widget.imageStore.load(
      widget.filePath,
      RawLayer.embeddedJpeg,
      priority: priority,
    );

    if (!mounted) {
      image?.dispose();
      return;
    }

    if (image != null) {
      setState(() {
        _embeddedJpegImage?.dispose();
        _embeddedJpegImage = image;
      });
    }
    widget.onEmbeddedJpegAvailability?.call(image != null);
  }

  void _applyScale(
    double scaleChange,
    Offset focalPoint, {
    bool lockAtFitScale = false,
  }) {
    if (scaleChange <= 0 || !scaleChange.isFinite) {
      return;
    }
    if ((scaleChange - 1).abs() < 0.0001) {
      return;
    }

    final direction = scaleChange > 1
        ? PreviewScaleDirection.zoomIn
        : PreviewScaleDirection.zoomOut;

    if (_isFitScaleLocked) {
      if (lockAtFitScale && direction == _fitScaleLockDirection) {
        _lockAtFitScale(direction);
        return;
      }
      _clearFitScaleLock();
    }

    final matrix = _transformationController.value.clone();
    final currentScale = matrix.getMaxScaleOnAxis();
    final targetScale = clampPreviewScale(currentScale * scaleChange);
    if (shouldResetPreviewPositionAtFitScale(
      currentScale: currentScale,
      targetScale: targetScale,
    )) {
      // Crossing the fitted size in either direction is a distinct step.
      // Pointer zoom stays here until its current scroll/pinch sequence ends.
      _transformationController.value = Matrix4.identity();
      if (lockAtFitScale) {
        _lockAtFitScale(direction);
      }
      return;
    }
    final effectiveScaleChange = targetScale / currentScale;
    if ((effectiveScaleChange - 1).abs() < 0.0001) {
      return;
    }

    final scaleMatrix = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(
        effectiveScaleChange,
        effectiveScaleChange,
        effectiveScaleChange,
        1,
      )
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _transformationController.value = scaleMatrix * matrix;
  }

  void _zoomBy(double scaleChange) {
    final size = context.size;
    if (size == null) {
      return;
    }
    _applyScale(scaleChange, size.center(Offset.zero));
  }

  void _resetView() {
    _clearFitScaleLock();
    _transformationController.value = Matrix4.identity();
    widget.onResetRotationRequested();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (event) {
        final scaleEvent = event as PointerScaleEvent;
        _applyScale(
          scaleEvent.scale,
          scaleEvent.localPosition,
          lockAtFitScale: true,
        );
      });
      return;
    }

    if (event is! PointerScrollEvent) {
      return;
    }

    final scrollDelta = event.scrollDelta;
    final primaryDelta = scrollDelta.dx.abs() > scrollDelta.dy.abs()
        ? scrollDelta.dx
        : scrollDelta.dy;
    if (primaryDelta == 0) {
      return;
    }

    final shouldZoom = isZoomModifierPressed();
    if (event.kind == PointerDeviceKind.trackpad && !shouldZoom) {
      // Let PageView consume trackpad scroll signals directly. On platforms
      // that emit these instead of pan/zoom events, this preserves follow.
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      scrollEvent.respond(allowPlatformDefault: false);
      if (shouldZoom) {
        _applyScale(
          primaryDelta < 0 ? 1.1 : 0.9,
          scrollEvent.localPosition,
          lockAtFitScale: true,
        );
      } else {
        widget.onSwitchRequest(primaryDelta > 0 ? 1 : -1);
      }
    });
  }

  void _handleTrackpadPanZoomStart(PointerPanZoomStartEvent event) {
    _lastTrackpadScale = 1;
    _isTrackpadScaling = false;
    // Once zoomed, InteractiveViewer owns two-finger panning of the image.
    // At the fit scale, drive PageView with the same drag activity used by
    // touch so page position stays directly under the gesture.
    _isTrackpadPageDrag = !_panEnabled;
    if (_isTrackpadPageDrag) {
      widget.onTrackpadPanStart(event);
    }
  }

  void _handleTrackpadPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale > 0 && event.scale.isFinite) {
      final scaleChange = event.scale / _lastTrackpadScale;
      _lastTrackpadScale = event.scale;
      if (_isTrackpadScaling ||
          (event.scale - 1).abs() >= previewTrackpadScaleSlop) {
        if (!_isTrackpadScaling && _isTrackpadPageDrag) {
          widget.onTrackpadPanCancel();
          _isTrackpadPageDrag = false;
        }
        _isTrackpadScaling = true;
        _applyScale(
          scaleChange,
          event.localPosition,
          lockAtFitScale: true,
        );
        return;
      }
    }

    if (_isTrackpadPageDrag) {
      widget.onTrackpadPanUpdate(event);
    }
  }

  void _handleTrackpadPanZoomEnd(PointerPanZoomEndEvent event) {
    if (_isTrackpadPageDrag && !_isTrackpadScaling) {
      widget.onTrackpadPanEnd(event);
    }
    _clearFitScaleLock();
    _isTrackpadPageDrag = false;
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    _checkPointers();
    // If touch, enable scaling (pinch)
    if (event.kind == PointerDeviceKind.touch) {
      if (!_scaleEnabled) {
        setState(() {
          _scaleEnabled = true;
        });
      }
    } else if (event.kind == PointerDeviceKind.mouse) {
      if (_scaleEnabled) {
        setState(() {
          _scaleEnabled = false;
        });
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    _checkPointers();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    _checkPointers();
  }

  void _checkPointers() {
    final shouldLock = _activePointers.length >= 2;
    widget.onScaleStateChanged?.call(shouldLock);
  }

  void _onPointerHover(PointerHoverEvent event) {
    // If mouse hover, disable scaling to prevent wheel zoom
    if (event.kind == PointerDeviceKind.mouse && _scaleEnabled) {
      setState(() {
        _scaleEnabled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        return Stack(
          children: [
            Listener(
              onPointerSignal: _handlePointerSignal,
              onPointerPanZoomStart: _handleTrackpadPanZoomStart,
              onPointerPanZoomUpdate: _handleTrackpadPanZoomUpdate,
              onPointerPanZoomEnd: _handleTrackpadPanZoomEnd,
              onPointerDown: _onPointerDown,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              onPointerHover: _onPointerHover,
              child: Center(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: kMinPreviewScale,
                  maxScale: kMaxPreviewScale,
                  panEnabled: _panEnabled,
                  scaleEnabled: _scaleEnabled,
                  child: RotatedBox(
                    quarterTurns: widget.rotationQuarterTurns,
                    child: _isShowingPairedJpeg
                        ? _buildBitmapPreview(
                            widget.mediaGroup.pairedJpeg!.path)
                        : widget.isRaw
                            ? _buildRawPreview()
                            : Stack(
                                fit: StackFit.expand,
                                children: [
                                  _buildBitmapPreview(widget.filePath)
                                ],
                              ),
                  ),
                ),
              ),
            ),
            if (widget.isActive && widget.showPreviewOverview && _isZoomed)
              Positioned(
                right: 12,
                bottom: widget.overviewBottomInset +
                    MediaQuery.paddingOf(context).bottom +
                    previewImageControlsHeight +
                    previewOverviewGap +
                    12,
                child: PreviewHoverReveal(
                  restingOpacity: widget.settings.previewOverlayOpacity,
                  child: PreviewOverviewMap(
                    image: RotatedBox(
                      quarterTurns: widget.rotationQuarterTurns,
                      child: _buildOverviewImage(),
                    ),
                    transformationController: _transformationController,
                    viewportSize: viewportSize,
                  ),
                ),
              ),
            Positioned(
              right: 12,
              bottom: MediaQuery.paddingOf(context).bottom + 12,
              child: PreviewHoverReveal(
                restingOpacity: widget.settings.previewOverlayOpacity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RawViewerColors.surface.withValues(alpha: 0.84),
                    border: Border.all(color: RawViewerColors.border),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DesktopIconButton(
                          icon: Icons.rotate_left,
                          tooltip: l10n.rotateImageCounterclockwiseTooltip,
                          onPressed: () => widget.onRotationRequested(-1),
                        ),
                        const SizedBox(width: 2),
                        DesktopIconButton(
                          icon: Icons.rotate_right,
                          tooltip: l10n.rotateImageTooltip,
                          onPressed: () => widget.onRotationRequested(1),
                        ),
                        const SizedBox(width: 5),
                        DesktopIconButton(
                          icon: Icons.zoom_in,
                          tooltip: l10n.zoomInImageTooltip,
                          onPressed: () => _zoomBy(previewControlZoomStep),
                        ),
                        const SizedBox(width: 2),
                        DesktopIconButton(
                          icon: Icons.zoom_out,
                          tooltip: l10n.zoomOutImageTooltip,
                          onPressed: () => _zoomBy(1 / previewControlZoomStep),
                        ),
                        const SizedBox(width: 2),
                        DesktopIconButton(
                          icon: Icons.filter_center_focus,
                          tooltip: l10n.resetImageViewTooltip,
                          onPressed: _resetView,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The single RAW image to paint, best available first.
  ///
  /// In embedded-JPEG mode the embedded JPEG wins, and the decoded layer only
  /// appears when this file has no embedded JPEG at all (the mode is greyed out
  /// and falls back rather than showing nothing). In decoded mode the decode
  /// wins once it lands, with the embedded JPEG as the interim sharp image.
  /// The cached thumbnail is the last resort in both.
  ViewerImage? get _displayedImage {
    if (_isShowingEmbeddedJpeg) {
      return _embeddedJpegImage ?? _decodedRawPreviewImage ?? _thumbnailImage;
    }
    return _decodedRawPreviewImage ?? _embeddedJpegImage ?? _thumbnailImage;
  }

  Widget _buildOverviewImage() {
    if (_isShowingPairedJpeg) {
      return _buildOverviewBitmap(widget.mediaGroup.pairedJpeg!.path);
    }
    if (widget.isRaw) {
      final image = _displayedImage;
      if (image != null) {
        return RawImage(
          image: image.image,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.low,
        );
      }
      return const SizedBox.shrink();
    }
    return _buildOverviewBitmap(widget.filePath);
  }

  Widget _buildOverviewBitmap(String filePath) {
    return Image(
      image: ResizeImage(
        FileImage(File(filePath)),
        width:
            (kPreviewOverviewMapWidth * MediaQuery.devicePixelRatioOf(context))
                .round(),
      ),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  /// Paints exactly one RAW image layer.
  ///
  /// The best available layer fully covers the ones beneath it, so stacking
  /// them would pay for a large overdraw every frame with nothing to show for
  /// it. The centred spinner only appears when there is genuinely nothing to
  /// display yet.
  Widget _buildRawPreview() {
    final displayed = _displayedImage;
    final isSharpeningInBackground = _isLoadingDecodedRawPreview &&
        displayed != null &&
        displayed != _decodedRawPreviewImage;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (displayed != null)
          RawImageWidget(
            image: displayed,
            fit: BoxFit.contain,
            heroTag: widget.isActive ? widget.filePath : null,
          ),
        if (displayed == null)
          const Center(
            child: ExcludeSemantics(child: CircularProgressIndicator()),
          )
        else if (isSharpeningInBackground)
          // Decoding in the background; keep showing what we already have.
          const Positioned(
            top: 24,
            left: 16,
            child: ExcludeSemantics(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white54),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBitmapPreview(String filePath) {
    final file = File(filePath);

    // Decoding a bitmap at full resolution costs width*height*4 bytes no matter
    // how small the window is — an 8000x6000 JPEG is ~192 MB. Cap the decode at
    // what the viewport can actually show, with headroom for zooming in.
    final mediaQuery = MediaQuery.of(context);
    final viewportWidth = mediaQuery.size.width * mediaQuery.devicePixelRatio;
    final fullDecodeWidth = bucketDecodeWidth(
      (viewportWidth * _bitmapZoomHeadroom).clamp(
        widget.thumbnailResizeWidth.toDouble(),
        _maxBitmapDecodeWidth,
      ),
    );

    Widget image = ValueListenableBuilder<bool>(
      valueListenable: widget.isFastScrolling,
      builder: (context, isFastScrolling, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Image(
              image: ResizeImage(
                FileImage(file),
                width: widget.thumbnailResizeWidth,
              ),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(Icons.broken_image, color: Colors.white),
              ),
            ),
            if (widget.isActive && !isFastScrolling)
              Image(
                image: ResizeImage(
                  FileImage(file),
                  width: fullDecodeWidth,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.broken_image, color: Colors.white),
                ),
              ),
          ],
        );
      },
    );

    // Only wrap the active image in a Hero to prevent duplicate Hero tags in the PageView
    if (widget.isActive) {
      return Hero(tag: widget.filePath, child: image);
    }
    return image;
  }
}

/// Extra resolution decoded beyond the viewport so zooming stays sharp.
const double _bitmapZoomHeadroom = 2.0;

/// Hard ceiling on bitmap decode width, in physical pixels.
const double _maxBitmapDecodeWidth = 4096;
