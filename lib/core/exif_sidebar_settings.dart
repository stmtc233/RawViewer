const double kDefaultExifSidebarWidth = 340;
const double kMinExifSidebarWidth = 280;
const double kMaxExifSidebarWidth = 640;

enum ExifSection { file, shooting, image, exif, gps, maker, thumbnail, other }

double normalizeExifSidebarWidth(double width) => width.isFinite
    ? width.clamp(kMinExifSidebarWidth, kMaxExifSidebarWidth).toDouble()
    : kDefaultExifSidebarWidth;

class ExifSidebarSettings {
  final bool visible;
  final double width;
  final Set<ExifSection> expandedSections;

  const ExifSidebarSettings({
    this.visible = false,
    this.width = kDefaultExifSidebarWidth,
    this.expandedSections = const {},
  });

  ExifSidebarSettings copyWith({
    bool? visible,
    double? width,
    Set<ExifSection>? expandedSections,
  }) =>
      ExifSidebarSettings(
        visible: visible ?? this.visible,
        width: normalizeExifSidebarWidth(width ?? this.width),
        expandedSections: expandedSections == null
            ? this.expandedSections
            : Set.unmodifiable(expandedSections),
      );
}
