import 'package:flutter/material.dart';

import '../viewer_image.dart';

/// Paints an already-decoded [ViewerImage].
///
/// Uses [RawImage] rather than [Image.memory] on purpose: the `ui.Image` is
/// already in hand, so the pixels land in the very frame this widget is built.
/// Going through `Image.memory` would re-enter the async codec path and leave a
/// blank gap over the preview scaffold on every page switch.
class RawImageWidget extends StatelessWidget {
  final ViewerImage image;
  final BoxFit? fit;
  final String? heroTag;

  const RawImageWidget({
    super.key,
    required this.image,
    this.fit,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    Widget painted = RawImage(
      image: image.image,
      fit: fit,
      filterQuality: FilterQuality.medium,
    );

    if (heroTag != null) {
      return Hero(
        tag: heroTag!,
        child: painted,
      );
    }
    return painted;
  }
}
