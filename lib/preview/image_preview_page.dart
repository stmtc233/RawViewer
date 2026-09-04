import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../core/decode_target.dart';
import '../core/media_timestamps.dart';
import '../core/media_types.dart';
import '../image_store.dart';
import '../l10n/app_localizations.dart';
import '../media_group.dart';
import '../native_lib.dart';
import '../settings_page.dart';
import '../ui/app_theme.dart';
import '../worker_service.dart';
import '../ui/desktop_controls.dart';
import '../ui/fast_page_scroll_physics.dart';
import 'preview_geometry.dart';
import 'preview_models.dart';
import 'single_image_preview.dart';
import 'widgets/preview_filmstrip.dart';
import 'widgets/preview_hover_reveal.dart';

class ImagePreviewPage extends StatefulWidget {
  final List<MediaGroup> mediaGroups;
  final int initialIndex;
  final int thumbnailResizeWidth;
  final ImageStore imageStore;
  final TimestampRepository timestampRepository;
  final ViewerSettings settings;
  final VoidCallback onClose;

  const ImagePreviewPage({
    super.key,
    required this.mediaGroups,
    required this.initialIndex,
    required this.thumbnailResizeWidth,
    required this.imageStore,
    required this.timestampRepository,
    required this.settings,
    required this.onClose,
  });

  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage> {
  late PageController _pageController;
  late int _currentIndex;
  late int _targetPage;
  bool _isLocked = false;
  bool _showPreviewFilmstrip = true;
  bool _showPreviewOverview = true;
  final Map<String, int> _rotationQuarterTurns = <String, int>{};
  final Map<String, PreviewSource> _previewSources =
      <String, PreviewSource>{};
  bool _isExportingEmbeddedJpeg = false;

  DateTime? _lastSwitchTime;
  Timer? _scrollStopTimer;
  Drag? _trackpadPageDrag;
  VelocityTracker? _trackpadVelocityTracker;
  Offset _lastTrackpadPan = Offset.zero;
  Duration? _lastTrackpadPanTimestamp;
  double _trackpadFlingVelocity = 0;
  // A notifier rather than setState: flipping this must not rebuild the whole
  // PageView (and every page in it) on each scroll burst.
  final ValueNotifier<bool> _isFastScrolling = ValueNotifier<bool>(false);
  late Future<MediaTimestampInfo> _currentTimestampFuture;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _targetPage = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _currentTimestampFuture = widget.timestampRepository.load(
      widget.mediaGroups[_currentIndex].primary.path,
    );
  }

  @override
  void dispose() {
    _scrollStopTimer?.cancel();
    _trackpadPageDrag?.cancel();
    _trackpadVelocityTracker = null;
    _isFastScrolling.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _currentTimestampFuture = widget.timestampRepository.load(
        widget.mediaGroups[_currentIndex].primary.path,
      );
      if ((_targetPage - index).abs() <= 1) {
        _targetPage = index;
      }
    });

    // We also preload here to cover cases where user swiped manually instead of mouse wheel
    _preloadThumbnails(index);
  }

  void _startTrackpadPageDrag(PointerPanZoomStartEvent event) {
    _trackpadPageDrag?.cancel();
    _trackpadVelocityTracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, Offset.zero);
    _lastTrackpadPan = Offset.zero;
    _lastTrackpadPanTimestamp = event.timeStamp;
    _trackpadFlingVelocity = 0;
    if (!_pageController.hasClients) {
      return;
    }

    _trackpadPageDrag = _pageController.position.drag(
      DragStartDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        sourceTimeStamp: event.timeStamp,
        kind: event.kind,
      ),
      () => _trackpadPageDrag = null,
    );
  }

  void _updateTrackpadPageDrag(PointerPanZoomUpdateEvent event) {
    final panDelta = event.localPanDelta.dx * trackpadPageDragSensitivity;
    final panPosition = event.localPan * trackpadPageDragSensitivity;
    _trackpadVelocityTracker?.addPosition(event.timeStamp, panPosition);
    final previousTimestamp = _lastTrackpadPanTimestamp;
    if (previousTimestamp != null) {
      final elapsed = event.timeStamp - previousTimestamp;
      if (elapsed > Duration.zero && elapsed.inMilliseconds <= 100) {
        final instantaneousVelocity = (panPosition.dx - _lastTrackpadPan.dx) /
            elapsed.inMicroseconds *
            Duration.microsecondsPerSecond;
        if (instantaneousVelocity.isFinite) {
          _trackpadFlingVelocity = _trackpadFlingVelocity == 0
              ? instantaneousVelocity
              : _trackpadFlingVelocity * 0.35 + instantaneousVelocity * 0.65;
        }
      }
    }
    _lastTrackpadPan = panPosition;
    _lastTrackpadPanTimestamp = event.timeStamp;
    if (panDelta == 0) {
      return;
    }

    _trackpadPageDrag?.update(
      DragUpdateDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        sourceTimeStamp: event.timeStamp,
        delta: Offset(panDelta, 0),
        primaryDelta: panDelta,
        kind: event.kind,
      ),
    );
  }

  void _endTrackpadPageDrag(PointerPanZoomEndEvent event) {
    final drag = _trackpadPageDrag;
    _trackpadPageDrag = null;
    final trackedVelocity =
        _trackpadVelocityTracker?.getVelocity().pixelsPerSecond.dx ?? 0;
    _trackpadVelocityTracker = null;
    final velocity = trackedVelocity.abs() >= trackpadFlingMinVelocity
        ? trackedVelocity
        : _trackpadFlingVelocity.abs() >= trackpadFlingMinVelocity
            ? _trackpadFlingVelocity
            : 0.0;
    drag?.end(
      DragEndDetails(
        globalPosition: event.position,
        localPosition: event.localPosition,
        velocity: Velocity(pixelsPerSecond: Offset(velocity, 0)),
        primaryVelocity: velocity,
      ),
    );
  }

  void _cancelTrackpadPageDrag() {
    _trackpadPageDrag?.cancel();
    _trackpadPageDrag = null;
    _trackpadVelocityTracker = null;
  }

  void _preloadThumbnails(int centerIndex, {bool isFastScrolling = false}) {
    final range = isFastScrolling ? 1 : 3;
    for (int i = 1; i <= range; i++) {
      _preloadIndex(centerIndex + i);
      _preloadIndex(centerIndex - i);
    }
  }

  void _preloadIndex(int index) {
    if (index < 0 || index >= widget.mediaGroups.length) return;

    final mediaFile = widget.mediaGroups[index].primary;
    final String filePath = mediaFile.path;

    if (mediaFile.isRaw) {
      // Warm a bounded thumbnail layer instead of several full-resolution RAW
      // images. The active page paints this cached layer immediately, then
      // upgrades itself in the background when needed.
      unawaited(widget.imageStore
          .load(
            filePath,
            RawLayer.fastPreview,
            targetWidth: _previewFilmstripDecodeWidth,
            priority: TaskPriority.low,
          )
          .then((image) => image?.dispose()));
    } else {
      // For bitmaps, preload the same low-res layer used by single preview
      if (mounted) {
        precacheImage(
          ResizeImage(
            FileImage(File(filePath)),
            width: widget.thumbnailResizeWidth,
          ),
          context,
        );
      }
    }
  }

  int get _previewFilmstripDecodeWidth => bucketDecodeWidth(
        kPreviewFilmstripItemWidth * MediaQuery.devicePixelRatioOf(context),
      );

  void _switchPage(int delta) {
    int newTarget = _targetPage + delta;
    if (newTarget < 0) newTarget = 0;
    if (newTarget >= widget.mediaGroups.length) {
      newTarget = widget.mediaGroups.length - 1;
    }

    if (newTarget == _targetPage && newTarget == _currentIndex) {
      return;
    }

    bool isAnimating = false;
    if (_pageController.position.haveDimensions) {
      final page = _pageController.page!;
      if ((page - page.round()).abs() > 0.05) {
        isAnimating = true;
      }
    }

    final now = DateTime.now();
    bool fastScroll = isAnimating ||
        (_lastSwitchTime != null &&
            now.difference(_lastSwitchTime!) <
                kImagePreviewRapidSwitchThreshold);
    _lastSwitchTime = now;

    _targetPage = newTarget;
    // Preload thumbnails IMMEDIATELY on scroll intention, rather than waiting for animation to hit 50%
    _preloadThumbnails(_targetPage,
        isFastScrolling: fastScroll || _isFastScrolling.value);

    // Touch and trackpad swipes move the PageView directly and never take this
    // branch. Disabling the setting therefore only removes animation from
    // discrete mouse-wheel navigation.
    if (!widget.settings.pageSwitchAnimationEnabled) {
      _scrollStopTimer?.cancel();
      _isFastScrolling.value = false;
      _pageController.jumpToPage(_targetPage);
      return;
    }

    void startFastScrollTimer() {
      _isFastScrolling.value = true;
      _scrollStopTimer?.cancel();
      _scrollStopTimer = Timer(kImagePreviewRapidSwitchSettleDelay, () {
        if (!mounted) return;
        _isFastScrolling.value = false;
        // Also ensure we correctly update target/index when stopping
        if (_pageController.page != _targetPage.toDouble()) {
          _pageController.jumpToPage(_targetPage);
        }
      });
    }

    if (fastScroll || _isFastScrolling.value) {
      startFastScrollTimer();
      _pageController.jumpToPage(_targetPage);
    } else {
      _pageController.animateToPage(
        _targetPage,
        duration: kImagePreviewPageSwitchDuration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _jumpToPage(int index) {
    if (index < 0 || index >= widget.mediaGroups.length) {
      return;
    }
    if (index == _currentIndex && index == _targetPage) {
      return;
    }

    _targetPage = index;
    _preloadThumbnails(index);
    _scrollStopTimer?.cancel();
    _isFastScrolling.value = false;

    if (!widget.settings.pageSwitchAnimationEnabled) {
      _pageController.jumpToPage(index);
      return;
    }

    _pageController.animateToPage(
      index,
      duration: kImagePreviewPageSwitchDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _rotateImage(String filePath, int quarterTurns) {
    setState(() {
      _rotationQuarterTurns[filePath] = rotateImageQuarterTurns(
        _rotationQuarterTurns[filePath] ?? 0,
        quarterTurns,
      );
    });
  }

  void _resetImageRotation(String filePath) {
    setState(() {
      _rotationQuarterTurns.remove(filePath);
    });
  }

  PreviewSource _previewSourceFor(MediaGroup mediaGroup) {
    return _previewSources[mediaGroup.primary.path] ??
        (widget.settings.preferFastPreviewForRaw
            ? PreviewSource.fastPreview
            : PreviewSource.decodedRaw);
  }

  void _selectPreviewSource(MediaGroup mediaGroup, PreviewSource source) {
    if (!mediaGroup.isRaw ||
        (source == PreviewSource.jpeg && !mediaGroup.hasPairedJpeg)) {
      return;
    }
    setState(() {
      _previewSources[mediaGroup.primary.path] = source;
    });
  }

  Future<void> _exportEmbeddedJpeg(String filePath) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isExportingEmbeddedJpeg = true;
    });

    try {
      final jpegBytes = await extractEmbeddedJpeg(filePath);
      if (!mounted) return;

      if (jpegBytes == null) {
        _showPreviewMessage(l10n.embeddedJpegNotFoundMessage);
        return;
      }

      final savedFile = await FilePicker.saveFile(
        fileName: embeddedJpegExportFileName(filePath),
        bytes: jpegBytes,
        mimeType: 'image/jpeg',
        dialogTitle: l10n.exportEmbeddedJpegDialogTitle,
        initialDirectory: Platform.isAndroid ? null : path.dirname(filePath),
      );
      if (!mounted || savedFile == null) return;

      _showPreviewMessage(l10n.embeddedJpegExportedMessage);
    } catch (error) {
      if (mounted) {
        _showPreviewMessage(
          l10n.embeddedJpegExportFailedMessage(
            _embeddedJpegExportErrorMessage(error),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingEmbeddedJpeg = false;
        });
      }
    }
  }

  void _showPreviewMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _embeddedJpegExportErrorMessage(Object error) {
    if (error is PlatformException) {
      return error.message ?? error.code;
    }
    return error.toString();
  }

  IconData _previewSourceIcon(PreviewSource source) {
    switch (source) {
      case PreviewSource.fastPreview:
        return Icons.bolt_outlined;
      case PreviewSource.decodedRaw:
        return Icons.camera_alt_outlined;
      case PreviewSource.jpeg:
        return Icons.image_outlined;
    }
  }

  String _previewSourceLabel(
    AppLocalizations l10n,
    PreviewSource source,
  ) {
    switch (source) {
      case PreviewSource.fastPreview:
        return l10n.fastPreviewShortLabel;
      case PreviewSource.decodedRaw:
        return l10n.rawShortLabel;
      case PreviewSource.jpeg:
        return 'JPG';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currentMediaGroup = widget.mediaGroups[_currentIndex];
    final currentFilePath = widget.mediaGroups[_currentIndex].primary.path;
    final currentPreviewSource = _previewSourceFor(currentMediaGroup);
    final previewTop =
        MediaQuery.paddingOf(context).top + kImagePreviewToolbarHeight;
    final pageDragDevices =
        Set<PointerDeviceKind>.from(ScrollConfiguration.of(context).dragDevices)
          ..remove(PointerDeviceKind.trackpad);
    return Scaffold(
      backgroundColor: RawViewerColors.previewBackground,
      body: Stack(
        children: [
          Positioned.fill(
            top: previewTop,
            bottom: _showPreviewFilmstrip
                ? kPreviewFilmstripHeight + MediaQuery.paddingOf(context).bottom
                : 0,
            child: PageView.builder(
              controller: _pageController,
              // Trackpad pages are moved from raw pan deltas so their position
              // remains directly coupled to the user's fingers.
              scrollBehavior: ScrollConfiguration.of(context).copyWith(
                dragDevices: pageDragDevices,
              ),
              physics: _isLocked
                  ? const NeverScrollableScrollPhysics()
                  : const FastPageScrollPhysics(),
              dragStartBehavior: DragStartBehavior.down,
              allowImplicitScrolling: true,
              padEnds: true,
              itemCount: widget.mediaGroups.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final mediaGroup = widget.mediaGroups[index];
                final filePath = mediaGroup.primary.path;
                return SingleImagePreview(
                  key: ValueKey(filePath),
                  mediaGroup: mediaGroup,
                  thumbnailResizeWidth: widget.thumbnailResizeWidth,
                  previewThumbnailResizeWidth: _previewFilmstripDecodeWidth,
                  imageStore: widget.imageStore,
                  settings: widget.settings,
                  rotationQuarterTurns: _rotationQuarterTurns[filePath] ?? 0,
                  previewSource: _previewSourceFor(mediaGroup),
                  onRotationRequested: (quarterTurns) =>
                      _rotateImage(filePath, quarterTurns),
                  onResetRotationRequested: () => _resetImageRotation(filePath),
                  onSwitchRequest: _switchPage,
                  onTrackpadPanStart: _startTrackpadPageDrag,
                  onTrackpadPanUpdate: _updateTrackpadPageDrag,
                  onTrackpadPanEnd: _endTrackpadPageDrag,
                  onTrackpadPanCancel: _cancelTrackpadPageDrag,
                  isActive: index == _currentIndex,
                  showPreviewOverview: _showPreviewOverview,
                  overviewBottomInset: 0,
                  isFastScrolling: _isFastScrolling,
                  onScaleStateChanged: (isScaling) {
                    if (_isLocked != isScaling) {
                      setState(() {
                        _isLocked = isScaling;
                      });
                    }
                  },
                );
              },
            ),
          ),
          if (_showPreviewFilmstrip)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: PreviewHoverReveal(
                restingOpacity: widget.settings.previewOverlayOpacity,
                child: PreviewFilmstrip(
                  mediaGroups: widget.mediaGroups,
                  currentIndex: _currentIndex,
                  imageStore: widget.imageStore,
                  decodeWidth: _previewFilmstripDecodeWidth,
                  centerCurrentThumbnailTooltip:
                      l10n.centerCurrentPreviewThumbnailTooltip,
                  onIndexSelected: _jumpToPage,
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PreviewHoverReveal(
              restingOpacity: widget.settings.previewOverlayOpacity,
              child: FutureBuilder<MediaTimestampInfo>(
                future: _currentTimestampFuture,
                builder: (context, snapshot) {
                  final timestampText = snapshot.hasData
                      ? snapshot.data!.format(widget.settings.timeDisplaySource)
                      : '---- -- -- --:--:--';
                  return Container(
                    decoration: BoxDecoration(
                      color: RawViewerColors.surface.withValues(alpha: 0.84),
                      border: const Border(
                        bottom: BorderSide(color: RawViewerColors.border),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: SizedBox(
                        height: kImagePreviewToolbarHeight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            children: [
                              DesktopIconButton(
                                icon: Icons.arrow_back,
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                onPressed: widget.onClose,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      path.basename(currentFilePath),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: RawViewerColors.text,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      timestampText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: RawViewerColors.mutedText,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              DesktopPopupMenuButton<PreviewDisplayControl>(
                                tooltip: l10n.previewDisplayControlsTooltip,
                                onSelected: (control) {
                                  setState(() {
                                    switch (control) {
                                      case PreviewDisplayControl.filmstrip:
                                        _showPreviewFilmstrip =
                                            !_showPreviewFilmstrip;
                                        break;
                                      case PreviewDisplayControl.overview:
                                        _showPreviewOverview =
                                            !_showPreviewOverview;
                                        break;
                                    }
                                  });
                                },
                                itemBuilder: (context) => [
                                  desktopPopupMenuItem(
                                    value: PreviewDisplayControl.filmstrip,
                                    icon: Icons.view_carousel_outlined,
                                    selected: _showPreviewFilmstrip,
                                    label: l10n.previewFilmstripTitle,
                                  ),
                                  desktopPopupMenuItem(
                                    value: PreviewDisplayControl.overview,
                                    icon: Icons.map_outlined,
                                    selected: _showPreviewOverview,
                                    label: l10n.previewOverviewTitle,
                                  ),
                                ],
                                child: DesktopPopupMenuTrigger(
                                  icon: Icons.tune,
                                  selected: _showPreviewFilmstrip ||
                                      _showPreviewOverview,
                                ),
                              ),
                              if (currentMediaGroup.isRaw) ...[
                                const SizedBox(width: 8),
                                DesktopPopupMenuButton<PreviewSource>(
                                  tooltip: l10n.rawPreviewSourceSectionTitle,
                                  initialValue: currentPreviewSource,
                                  onSelected: (source) => _selectPreviewSource(
                                    currentMediaGroup,
                                    source,
                                  ),
                                  child: DesktopPopupMenuLabelTrigger(
                                    icon: _previewSourceIcon(
                                      currentPreviewSource,
                                    ),
                                    label: _previewSourceLabel(
                                      l10n,
                                      currentPreviewSource,
                                    ),
                                  ),
                                  itemBuilder: (context) => [
                                    desktopPopupMenuItem(
                                      value: PreviewSource.fastPreview,
                                      icon: Icons.bolt_outlined,
                                      selected: currentPreviewSource ==
                                          PreviewSource.fastPreview,
                                      label: l10n.fastPreviewShortLabel,
                                    ),
                                    desktopPopupMenuItem(
                                      value: PreviewSource.decodedRaw,
                                      icon: Icons.camera_alt_outlined,
                                      selected: currentPreviewSource ==
                                          PreviewSource.decodedRaw,
                                      label: l10n.rawShortLabel,
                                    ),
                                    if (currentMediaGroup.hasPairedJpeg)
                                      desktopPopupMenuItem(
                                        value: PreviewSource.jpeg,
                                        icon: Icons.image_outlined,
                                        selected: currentPreviewSource ==
                                            PreviewSource.jpeg,
                                        label: 'JPG',
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                DesktopPopupMenuButton<PreviewAction>(
                                  tooltip: l10n.moreActionsTooltip,
                                  enabled: !_isExportingEmbeddedJpeg,
                                  onSelected: (action) {
                                    switch (action) {
                                      case PreviewAction.exportEmbeddedJpeg:
                                        unawaited(
                                          _exportEmbeddedJpeg(
                                            currentMediaGroup.primary.path,
                                          ),
                                        );
                                        break;
                                    }
                                  },
                                  child: DesktopPopupMenuTrigger(
                                    icon: _isExportingEmbeddedJpeg
                                        ? Icons.downloading_outlined
                                        : Icons.more_vert,
                                  ),
                                  itemBuilder: (context) => [
                                    desktopPopupMenuItem(
                                      value: PreviewAction.exportEmbeddedJpeg,
                                      icon: Icons.download_outlined,
                                      label: l10n.exportEmbeddedJpegMenuItem,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

