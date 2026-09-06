import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../image_store.dart';
import '../../core/rating_filter.dart';
import '../../rating_badge.dart';
import '../../media_group.dart';
import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';
import '../../viewer_image.dart';
import '../../worker_service.dart';
import '../preview_geometry.dart';

class PreviewFilmstrip extends StatefulWidget {
  final List<MediaGroup> mediaGroups;
  final int currentIndex;
  final ImageStore imageStore;
  final double height;
  final int decodeWidth;
  final String centerCurrentThumbnailTooltip;
  final ValueChanged<int> onIndexSelected;
  final ValueChanged<int>? onFastIndexSelected;
  final Widget? controls;
  final RatingRepository? ratingRepository;
  final bool showRatings;

  const PreviewFilmstrip({
    super.key,
    required this.mediaGroups,
    required this.currentIndex,
    required this.imageStore,
    required this.height,
    required this.decodeWidth,
    required this.centerCurrentThumbnailTooltip,
    required this.onIndexSelected,
    this.onFastIndexSelected,
    this.controls,
    this.ratingRepository,
    this.showRatings = true,
  });

  @override
  State<PreviewFilmstrip> createState() => _PreviewFilmstripState();
}

class _PreviewFilmstripState extends State<PreviewFilmstrip> {
  late final ScrollController _scrollController;
  double? _lastViewportWidth;
  double _sidePadding = 0;
  bool _showLeadingCenterArrow = false;
  bool _showTrailingCenterArrow = false;
  bool _centerRequestScheduled = false;

  double get _itemWidth => previewFilmstripThumbnailSize(widget.height).width;
  double get _itemExtent => _itemWidth + 8;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_updateCenterArrowVisibility);
    _scheduleCenterCurrent(animated: false);
  }

  @override
  void didUpdateWidget(PreviewFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.mediaGroups != widget.mediaGroups ||
        oldWidget.height != widget.height) {
      _scheduleCenterCurrent(animated: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateCenterArrowVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleCenterCurrent({required bool animated}) {
    if (_centerRequestScheduled) {
      return;
    }
    _centerRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerRequestScheduled = false;
      if (!mounted) {
        return;
      }
      _centerCurrent(animated: animated);
    });
  }

  void _centerCurrent({required bool animated}) {
    if (!_scrollController.hasClients || widget.mediaGroups.isEmpty) {
      _scheduleCenterCurrent(animated: animated);
      return;
    }

    final position = _scrollController.position;
    final maxScrollExtent = position.maxScrollExtent;
    final itemStart = _sidePadding + widget.currentIndex * _itemExtent;
    final targetOffset =
        (itemStart + _itemWidth / 2 - position.viewportDimension / 2)
            .clamp(0.0, maxScrollExtent)
            .toDouble();
    if ((targetOffset - _scrollController.offset).abs() < 0.5) {
      _updateCenterArrowVisibility();
      return;
    }

    if (animated) {
      unawaited(_scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      ));
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  void _updateCenterArrowVisibility() {
    if (!_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final itemStart = _sidePadding + widget.currentIndex * _itemExtent;
    final itemEnd = itemStart + _itemWidth;
    final viewportStart = position.pixels;
    final viewportEnd = viewportStart + position.viewportDimension;
    final showLeading =
        itemStart < viewportStart - previewFilmstripVisibilityEpsilon;
    final showTrailing =
        itemEnd > viewportEnd + previewFilmstripVisibilityEpsilon;

    if (showLeading == _showLeadingCenterArrow &&
        showTrailing == _showTrailingCenterArrow) {
      return;
    }

    setState(() {
      _showLeadingCenterArrow = showLeading;
      _showTrailingCenterArrow = showTrailing;
    });
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_scrollController.hasClients || widget.mediaGroups.isEmpty) return;
    final delta = details.primaryDelta ?? 0;
    if (delta != 0) {
      final nextOffset = (_scrollController.offset - delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(nextOffset);
    }
    final position = _scrollController.position;
    final centerX = _scrollController.offset + position.viewportDimension / 2;
    final index = ((centerX - _sidePadding - _itemWidth / 2) / _itemExtent)
        .round()
        .clamp(0, widget.mediaGroups.length - 1);
    widget.onFastIndexSelected?.call(index);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) {
      return;
    }

    final scrollDelta = event.scrollDelta;
    // A conventional mouse wheel reports vertical deltas, while some
    // pointing devices report horizontal deltas directly. Use whichever
    // axis carries the greater movement and apply it to this horizontal
    // filmstrip.
    final delta = scrollDelta.dx.abs() > scrollDelta.dy.abs()
        ? scrollDelta.dx
        : scrollDelta.dy;
    if (delta == 0) {
      return;
    }

    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scrollEvent = event as PointerScrollEvent;
      scrollEvent.respond(allowPlatformDefault: false);
      _scrollController.position.pointerScroll(delta);
    });
  }

  Widget _buildCenterArrow({required bool leading}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RawViewerColors.surface.withValues(alpha: 0.94),
        border: Border.all(color: RawViewerColors.border),
        borderRadius: BorderRadius.circular(5),
      ),
      child: DesktopIconButton(
        key: ValueKey(
          leading
              ? 'preview-filmstrip-center-current-leading'
              : 'preview-filmstrip-center-current-trailing',
        ),
        icon: leading ? Icons.chevron_left : Icons.chevron_right,
        tooltip: widget.centerCurrentThumbnailTooltip,
        onPressed: () => _centerCurrent(animated: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (_lastViewportWidth != constraints.maxWidth) {
          _lastViewportWidth = constraints.maxWidth;
          _scheduleCenterCurrent(animated: false);
        }
        final viewportWidth = math.max(0.0, constraints.maxWidth - 24);
        final thumbnailSize = previewFilmstripThumbnailSize(widget.height);
        final sidePadding = math.max(
          0.0,
          (viewportWidth - thumbnailSize.width) / 2,
        );
        _sidePadding = sidePadding;
        return Container(
          key: const ValueKey('preview-filmstrip-panel'),
          height: widget.height + bottomPadding,
          padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPadding + 10),
          decoration: BoxDecoration(
            color: RawViewerColors.surface.withValues(alpha: 0.96),
            border: const Border(
              top: BorderSide(color: RawViewerColors.border),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerSignal: _handlePointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: _handleHorizontalDragUpdate,
                  child: ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbColor: WidgetStatePropertyAll(
                        RawViewerColors.mutedText.withValues(alpha: 0.65),
                      ),
                      mainAxisMargin: previewFilmstripScrollbarMainAxisMargin,
                    ),
                    child: Scrollbar(
                      controller: _scrollController,
                      scrollbarOrientation: ScrollbarOrientation.bottom,
                      thumbVisibility: false,
                      trackVisibility: false,
                      thickness: previewFilmstripScrollbarThickness,
                      radius: const Radius.circular(
                        previewFilmstripScrollbarThickness / 2,
                      ),
                      child: Padding(
                        // Reserve the thumb's cross-axis space so it does not
                        // paint over the bottom edge of the thumbnails.
                        padding: const EdgeInsets.only(
                          bottom: previewFilmstripScrollbarThickness,
                        ),
                        child: ListView.builder(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const ClampingScrollPhysics(),
                          padding:
                              EdgeInsets.symmetric(horizontal: sidePadding),
                          scrollCacheExtent: ScrollCacheExtent.pixels(
                            _itemExtent * 4,
                          ),
                          itemExtent: _itemExtent,
                          itemCount: widget.mediaGroups.length,
                          itemBuilder: (context, index) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: thumbnailSize.width,
                                  height: thumbnailSize.height,
                                  child: _PreviewFilmstripThumbnail(
                                    key: ValueKey(
                                      widget.mediaGroups[index].primary.path,
                                    ),
                                    mediaGroup: widget.mediaGroups[index],
                                    imageStore: widget.imageStore,
                                    decodeWidth: widget.decodeWidth,
                                    selected: index == widget.currentIndex,
                                    ratingRepository: widget.ratingRepository,
                                    showRatings: widget.showRatings,
                                    onTap: () => widget.onIndexSelected(index),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_showLeadingCenterArrow)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildCenterArrow(leading: true),
                  ),
                ),
              if (_showTrailingCenterArrow)
                Positioned(
                  right:
                      widget.controls == null ? 0 : desktopControlSize * 2 + 4,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _buildCenterArrow(leading: false),
                  ),
                ),
              if (widget.controls != null)
                Positioned(
                  top: 0,
                  right: 0,
                  child: widget.controls!,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewFilmstripThumbnail extends StatefulWidget {
  final MediaGroup mediaGroup;
  final ImageStore imageStore;
  final int decodeWidth;
  final bool selected;
  final RatingRepository? ratingRepository;
  final bool showRatings;
  final VoidCallback onTap;

  const _PreviewFilmstripThumbnail({
    super.key,
    required this.mediaGroup,
    required this.imageStore,
    required this.decodeWidth,
    required this.selected,
    required this.ratingRepository,
    required this.showRatings,
    required this.onTap,
  });

  @override
  State<_PreviewFilmstripThumbnail> createState() =>
      _PreviewFilmstripThumbnailState();
}

class _PreviewFilmstripThumbnailState
    extends State<_PreviewFilmstripThumbnail> {
  ViewerImage? _rawImage;
  bool _failed = false;
  int _generation = 0;

  String get _filePath => widget.mediaGroup.primary.path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PreviewFilmstripThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_filePath != oldWidget.mediaGroup.primary.path ||
        widget.decodeWidth != oldWidget.decodeWidth) {
      _generation++;
      _rawImage?.dispose();
      _rawImage = null;
      _failed = false;
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _rawImage?.dispose();
    super.dispose();
  }

  void _load() {
    if (!widget.mediaGroup.isRaw) {
      return;
    }

    final generation = _generation;
    unawaited(widget.imageStore
        .load(
      _filePath,
      RawLayer.thumbnail,
      targetWidth: widget.decodeWidth,
      priority: TaskPriority.low,
    )
        .then((image) {
      if (!mounted || generation != _generation) {
        image?.dispose();
        return;
      }
      setState(() {
        _rawImage = image;
        _failed = image == null;
      });
    }));
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (widget.mediaGroup.isRaw) {
      image = _rawImage == null
          ? Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: RawViewerColors.raisedSurface),
                Center(
                  child: _failed
                      ? const Icon(Icons.broken_image_outlined,
                          color: RawViewerColors.mutedText, size: 18)
                      : const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              ],
            )
          : RawImage(
              image: _rawImage!.image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
            );
    } else {
      image = Image(
        image: ResizeImage(
          FileImage(File(_filePath)),
          width: widget.decodeWidth,
        ),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => Container(
          color: RawViewerColors.raisedSurface,
          child: const Icon(Icons.broken_image_outlined,
              color: RawViewerColors.mutedText, size: 18),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(5),
        splashColor: RawViewerColors.accentMuted,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: image,
            ),
            if (widget.showRatings && widget.ratingRepository != null)
              Positioned(
                left: 4,
                right: 4,
                bottom: 4,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: RatingBadge(
                    filePath: _filePath,
                    repository: widget.ratingRepository!,
                  ),
                ),
              ),
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: widget.selected
                        ? RawViewerColors.accent
                        : RawViewerColors.border,
                    width: widget.selected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
