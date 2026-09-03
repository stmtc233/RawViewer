import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

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

    return PopupMenuButton<MediaFilter>(
      initialValue: selectedFilter,
      enabled: totalCount > 0,
      tooltip: l10n.mediaFilterTooltip,
      icon: Icon(
        selectedFilter == MediaFilter.all
            ? Icons.filter_alt_outlined
            : Icons.filter_alt,
      ),
      onSelected: onSelected,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: MediaFilter.adaptive,
          checked: selectedFilter == MediaFilter.adaptive,
          child: Text(l10n.mediaFilterAdaptive(adaptiveCount)),
        ),
        CheckedPopupMenuItem(
          value: MediaFilter.all,
          checked: selectedFilter == MediaFilter.all,
          child: Text(l10n.mediaFilterAll(totalCount)),
        ),
        CheckedPopupMenuItem(
          value: MediaFilter.raw,
          checked: selectedFilter == MediaFilter.raw,
          child: Text(l10n.mediaFilterRaw(rawCount)),
        ),
        CheckedPopupMenuItem(
          value: MediaFilter.images,
          checked: selectedFilter == MediaFilter.images,
          child: Text(l10n.mediaFilterImages(imageCount)),
        ),
      ],
    );
  }
}
