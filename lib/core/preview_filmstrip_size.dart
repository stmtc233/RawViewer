const double kPreviewFilmstripHeight = 88;
const double kMinPreviewFilmstripHeight = 72;
const double kMaxPreviewFilmstripHeight = 320;

/// Bounds the saved preference independently of the current window size.
double normalizePreviewFilmstripHeight(double height) {
  return height.isFinite
      ? height
          .clamp(kMinPreviewFilmstripHeight, kMaxPreviewFilmstripHeight)
          .toDouble()
      : kPreviewFilmstripHeight;
}
