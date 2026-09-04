/// Granularity of decode-target widths, in physical pixels.
const int kDecodeWidthBucket = 128;

/// Rounds a desired decode width up to the next [kDecodeWidthBucket] step.
///
/// Decode targets double as cache keys, so a continuously-varying width (window
/// resize, DPR changes) would otherwise invalidate every cached image.
int bucketDecodeWidth(double width) {
  if (width <= kDecodeWidthBucket) return kDecodeWidthBucket;
  return (width / kDecodeWidthBucket).ceil() * kDecodeWidthBucket;
}
