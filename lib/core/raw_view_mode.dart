/// Which image the preview shows for a RAW file.
///
/// This is the user-facing choice behind the preview's top-right switch. It is
/// a single app-wide preference (persisted in `PreferencesRepository`), not
/// per-file state.
///
/// Lives in `core/` because the settings model, the preferences repository and
/// the preview all need it, and `core/` may not depend on `preview/`.
enum RawViewMode {
  /// The JPEG the camera embedded in the RAW container, shown as-is.
  ///
  /// Unavailable for RAW files that carry no embedded JPEG.
  embeddedJpeg,

  /// LibRaw's own decode of the RAW data. Always available for a RAW file.
  decodedRaw,

  /// The sibling `.jpg` shot alongside the RAW (RAW+JPEG shooting).
  ///
  /// Unavailable when the group has no paired JPEG.
  pairedJpeg,
}

/// Narrows [preferred] to a mode this particular file can actually display.
///
/// Only [RawViewMode.decodedRaw] is available for every RAW file, so it is the
/// fallback: an app-wide preference of `embeddedJpeg` must still show something
/// for a file whose RAW carries no embedded JPEG, and likewise for `pairedJpeg`
/// on a file that was not shot RAW+JPEG.
RawViewMode resolveRawViewMode({
  required RawViewMode preferred,
  required bool hasEmbeddedJpeg,
  required bool hasPairedJpeg,
}) {
  return switch (preferred) {
    RawViewMode.embeddedJpeg when !hasEmbeddedJpeg => RawViewMode.decodedRaw,
    RawViewMode.pairedJpeg when !hasPairedJpeg => RawViewMode.decodedRaw,
    _ => preferred,
  };
}

/// Whether [mode] can be selected for a file with these sources.
///
/// The preview renders every mode in its switch and greys out the unavailable
/// ones, so the menu never changes shape between files.
bool isRawViewModeAvailable(
  RawViewMode mode, {
  required bool hasEmbeddedJpeg,
  required bool hasPairedJpeg,
}) {
  return switch (mode) {
    RawViewMode.embeddedJpeg => hasEmbeddedJpeg,
    RawViewMode.decodedRaw => true,
    RawViewMode.pairedJpeg => hasPairedJpeg,
  };
}
