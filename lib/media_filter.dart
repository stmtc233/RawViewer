import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'ui/desktop_controls.dart';

enum MediaFilter {
  adaptive,
  all,
  raw,
  images;

  bool includes({required bool isRaw}) {
    return switch (this) {
      MediaFilter.adaptive => true,
      MediaFilter.all => true,
      MediaFilter.raw => isRaw,
      MediaFilter.images => !isRaw,
    };
  }
}

const defaultMediaFilter = MediaFilter.adaptive;

class MediaFilterButton extends StatelessWidget {
  final MediaFilter selectedFilter;
  final int adaptiveCount;
  final int rawCount;
  final int imageCount;
  final ValueChanged<MediaFilter> onSelected;

  const MediaFilterButton({
    super.key,
    required this.selectedFilter,
    required this.adaptiveCount,
    required this.rawCount,
    required this.imageCount,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalCount = rawCount + imageCount;

    return DesktopPopupMenuButton<MediaFilter>(
      enabled: totalCount > 0,
      tooltip: l10n.mediaFilterTooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        desktopPopupMenuItem(
          value: MediaFilter.adaptive,
          icon: Icons.auto_awesome_motion_outlined,
          selected: selectedFilter == MediaFilter.adaptive,
          label: l10n.mediaFilterAdaptive(adaptiveCount),
        ),
        desktopPopupMenuItem(
          value: MediaFilter.all,
          icon: Icons.collections_outlined,
          selected: selectedFilter == MediaFilter.all,
          label: l10n.mediaFilterAll(totalCount),
        ),
        desktopPopupMenuItem(
          value: MediaFilter.raw,
          icon: Icons.camera_alt_outlined,
          selected: selectedFilter == MediaFilter.raw,
          label: l10n.mediaFilterRaw(rawCount),
        ),
        desktopPopupMenuItem(
          value: MediaFilter.images,
          icon: Icons.image_outlined,
          selected: selectedFilter == MediaFilter.images,
          label: l10n.mediaFilterImages(imageCount),
        ),
      ],
      child: DesktopPopupMenuTrigger(
        icon: selectedFilter == MediaFilter.all
            ? Icons.filter_alt_outlined
            : Icons.filter_alt,
        selected: selectedFilter != MediaFilter.all,
      ),
    );
  }
}
