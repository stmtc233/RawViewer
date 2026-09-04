import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/media_timestamps.dart';
import '../../image_store.dart';
import '../../l10n/app_localizations.dart';
import '../../media_group.dart';
import '../../settings_page.dart';
import '../../ui/raw_image_widget.dart';
import '../../viewer_image.dart';

class MediaThumbnailTile extends StatefulWidget {
  final MediaFile mediaFile;
  final bool hasPairedJpeg;
  final ViewerSettings settings;
  final TimestampRepository timestampRepository;
  final int resizeWidth;
  final ImageStore imageStore;
  final ValueChanged<double>? onAspectRatioChanged;
  final VoidCallback onTap;

  const MediaThumbnailTile({
    super.key,
    required this.mediaFile,
    required this.hasPairedJpeg,
    required this.settings,
    required this.timestampRepository,
    required this.resizeWidth,
    required this.imageStore,
    this.onAspectRatioChanged,
    required this.onTap,
  });

  String get filePath => mediaFile.path;

  @override
  State<MediaThumbnailTile> createState() => _MediaThumbnailTileState();
}

class _MediaThumbnailTileState extends State<MediaThumbnailTile> {
  ViewerImage? _fastPreview;
  bool _failed = false;
  ImageStream? _bitmapImageStream;
  ImageStreamListener? _bitmapImageListener;

  /// Incremented whenever this tile is recycled or disposed, so a load that
  /// completes afterwards can tell that its result is no longer wanted.
  int _generation = 0;
  late Future<MediaTimestampInfo> _timestampFuture;

  @override
  void initState() {
    super.initState();
    _startLoad();
    _timestampFuture = widget.timestampRepository.load(widget.filePath);
  }

  @override
  void didUpdateWidget(MediaThumbnailTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.filePath != oldWidget.filePath ||
        widget.resizeWidth != oldWidget.resizeWidth) {
      _generation++;
      _clearPreview();
      _stopBitmapAspectRatioLoad();
      _failed = false;
      _startLoad();
      if (widget.filePath != oldWidget.filePath) {
        _timestampFuture = widget.timestampRepository.load(widget.filePath);
      }
    } else if (widget.onAspectRatioChanged != null &&
        oldWidget.onAspectRatioChanged == null) {
      if (widget.mediaFile.isRaw) {
        final preview = _fastPreview;
        if (preview != null) {
          _reportAspectRatio(preview.width / preview.height);
        }
      } else {
        _startBitmapAspectRatioLoad();
      }
    } else if (widget.onAspectRatioChanged == null &&
        oldWidget.onAspectRatioChanged != null) {
      _stopBitmapAspectRatioLoad();
    } else if (widget.settings.timeDisplaySource !=
        oldWidget.settings.timeDisplaySource) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _generation++; // Discard any in-flight result for this tile.
    _stopBitmapAspectRatioLoad();
    _clearPreview();
    super.dispose();
  }

  void _clearPreview() {
    _fastPreview?.dispose();
    _fastPreview = null;
  }

  void _startLoad() {
    // Bitmap files go through Flutter's own file/image pipeline.
    if (!widget.mediaFile.isRaw) {
      _startBitmapAspectRatioLoad();
      return;
    }

    // A cache hit resolves synchronously, so the very first frame already has
    // the image rather than flashing a placeholder.
    final cached = widget.imageStore.peek(widget.filePath, RawLayer.fastPreview,
        targetWidth: widget.resizeWidth);
    if (cached != null) {
      _fastPreview = cached;
      _reportAspectRatio(cached.width / cached.height);
      return;
    }

    unawaited(_loadRawFastPreview(_generation));
  }

  Future<void> _loadRawFastPreview(int generation) async {
    // This layer prefers embedded preview data and falls back to a fast
    // RAW-generated preview when the file has no embedded preview.
    //
    // The task is intentionally not cancelled when this tile is recycled: the
    // worker dedupes fast previews by path, so cancelling would also resolve
    // another tile's shared request to null. Scrolling past is instead handled
    // by ignoring a stale result via [generation].
    final image = await widget.imageStore.load(
      widget.filePath,
      RawLayer.fastPreview,
      targetWidth: widget.resizeWidth,
    );

    if (!mounted || generation != _generation) {
      image?.dispose();
      return;
    }

    setState(() {
      _clearPreview();
      _fastPreview = image;
      _failed = image == null;
    });
    if (image != null) {
      _reportAspectRatio(image.width / image.height);
    }
  }

  void _startBitmapAspectRatioLoad() {
    if (widget.onAspectRatioChanged == null) {
      return;
    }

    final imageProvider = ResizeImage(
      FileImage(File(widget.filePath)),
      width: widget.resizeWidth,
    );
    final imageStream = imageProvider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((imageInfo, _) {
      _reportAspectRatio(imageInfo.image.width / imageInfo.image.height);
    });
    _bitmapImageStream = imageStream;
    _bitmapImageListener = listener;
    imageStream.addListener(listener);
  }

  void _stopBitmapAspectRatioLoad() {
    final imageStream = _bitmapImageStream;
    final listener = _bitmapImageListener;
    if (imageStream != null && listener != null) {
      imageStream.removeListener(listener);
    }
    _bitmapImageStream = null;
    _bitmapImageListener = null;
  }

  void _reportAspectRatio(double aspectRatio) {
    widget.onAspectRatioChanged?.call(aspectRatio);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: path.basename(widget.filePath),
      button: true,
      onTap: widget.onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildContent(),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                      stops: [0.55, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        path.basename(widget.filePath),
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.1,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      FutureBuilder<MediaTimestampInfo>(
                        future: _timestampFuture,
                        builder: (context, snapshot) {
                          final text = snapshot.hasData
                              ? snapshot.data!
                                  .format(widget.settings.timeDisplaySource)
                              : '---- -- -- --:--:--';
                          return Text(
                            text,
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1,
                              color: Color(0xFFD2D9DD),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (widget.mediaFile.isRaw)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 30,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xE6171A1E),
                        border: Border.all(color: const Color(0xFF525A62)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        widget.hasPairedJpeg
                            ? AppLocalizations.of(context)!.rawJpegShortLabel
                            : AppLocalizations.of(context)!.rawShortLabel,
                        style: const TextStyle(
                          color: Color(0xFFE5E9EC),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // Bitmap files: use Flutter's built-in image pipeline with resize
    if (!widget.mediaFile.isRaw) {
      return _buildBitmapThumbnail();
    }

    final preview = _fastPreview;
    if (preview != null) {
      return RawImageWidget(
        image: preview,
        fit: BoxFit.cover,
        heroTag: widget.filePath,
      );
    }

    if (_failed) {
      return Container(
        color: Colors.grey[800],
        child: const Center(child: Icon(Icons.broken_image, size: 20)),
      );
    }

    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildBitmapThumbnail() {
    Widget image = Image(
      image: ResizeImage(
        FileImage(File(widget.filePath)),
        width: widget.resizeWidth,
      ),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.grey[800],
        child: const Center(child: Icon(Icons.broken_image, size: 20)),
      ),
    );
    return Hero(tag: widget.filePath, child: image);
  }
}

