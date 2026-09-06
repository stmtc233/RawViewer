import 'package:flutter/material.dart';

import '../../core/preferences_repository.dart';
import '../../media_filter.dart';
import '../../core/rating_filter.dart';
import '../../rating_filter_button.dart';
import '../../media_sort.dart';
import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';

class DesktopCommandBar extends StatelessWidget {
  final String title;
  final String openFolderLabel;
  final String openFilesLabel;
  final String openCurrentFolderLabel;
  final String recentItemsTitle;
  final String noRecentItemsLabel;
  final String moreActionsTooltip;
  final String settingsTooltip;
  final MediaFilter selectedMediaFilter;
  final RatingFilter selectedRatingFilter;
  final bool showRatings;
  final ValueChanged<RatingFilter> onRatingFilterSelected;
  final ValueChanged<bool> onShowRatingsChanged;
  final bool hideUnratedRatings;
  final ValueChanged<bool> onHideUnratedRatingsChanged;
  final MediaSortOrder selectedMediaSortOrder;
  final int adaptiveCount;
  final int rawCount;
  final int imageCount;
  final ValueChanged<MediaFilter> onMediaFilterSelected;
  final ValueChanged<MediaSortOrder> onMediaSortOrderSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;
  final List<RecentOpenItem> recentOpenItems;
  final ValueChanged<RecentOpenItem> onRecentOpenItemSelected;

  const DesktopCommandBar({
    super.key,
    required this.title,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.recentItemsTitle,
    required this.noRecentItemsLabel,
    required this.moreActionsTooltip,
    required this.settingsTooltip,
    required this.selectedMediaFilter,
    this.selectedRatingFilter = RatingFilter.all,
    this.showRatings = true,
    required this.onRatingFilterSelected,
    required this.onShowRatingsChanged,
    this.hideUnratedRatings = true,
    required this.onHideUnratedRatingsChanged,
    required this.selectedMediaSortOrder,
    required this.adaptiveCount,
    required this.rawCount,
    required this.imageCount,
    required this.onMediaFilterSelected,
    required this.onMediaSortOrderSelected,
    required this.onOpenSettings,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
    required this.recentOpenItems,
    required this.onRecentOpenItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        return Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: RawViewerColors.surface,
            border: Border(bottom: BorderSide(color: RawViewerColors.border)),
          ),
          child: Row(
            children: [
              GalleryActionsMenu(
                tooltip: moreActionsTooltip,
                openFolderLabel: openFolderLabel,
                openFilesLabel: openFilesLabel,
                openCurrentFolderLabel: openCurrentFolderLabel,
                recentItemsTitle: recentItemsTitle,
                noRecentItemsLabel: noRecentItemsLabel,
                onOpenFiles: onOpenFiles,
                onOpenFolder: onOpenFolder,
                onOpenCurrentFolder: onOpenCurrentFolder,
                recentOpenItems: recentOpenItems,
                onRecentOpenItemSelected: onRecentOpenItemSelected,
              ),
              const SizedBox(width: 4),
              const Icon(Icons.photo_library_outlined,
                  color: RawViewerColors.accent, size: 19),
              if (!compact) ...[
                const SizedBox(width: 8),
                const Text(
                  'RAW VIEWER',
                  style: TextStyle(
                    color: RawViewerColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 16),
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(color: RawViewerColors.border),
                ),
                const SizedBox(width: 12),
              ],
              if (!compact)
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RawViewerColors.mutedText,
                      fontSize: 12,
                    ),
                  ),
                )
              else
                const Spacer(),
              MediaFilterButton(
                selectedFilter: selectedMediaFilter,
                adaptiveCount: adaptiveCount,
                rawCount: rawCount,
                imageCount: imageCount,
                onSelected: onMediaFilterSelected,
              ),
              RatingFilterButton(
                selected: selectedRatingFilter,
                onSelected: onRatingFilterSelected,
                showRatings: showRatings,
                onShowRatingsChanged: onShowRatingsChanged,
                hideUnratedRatings: hideUnratedRatings,
                onHideUnratedRatingsChanged: onHideUnratedRatingsChanged,
              ),
              const SizedBox(width: 4),
              MediaSortButton(
                selectedSortOrder: selectedMediaSortOrder,
                enabled: rawCount + imageCount > 0,
                onSelected: onMediaSortOrderSelected,
              ),
              const SizedBox(width: 8),
              if (!compact)
                const SizedBox(
                  height: 20,
                  child: VerticalDivider(color: RawViewerColors.border),
                ),
              if (!compact) const SizedBox(width: 8),
              DesktopIconButton(
                icon: Icons.tune,
                tooltip: settingsTooltip,
                onPressed: onOpenSettings,
              ),
            ],
          ),
        );
      },
    );
  }
}

enum GalleryAction { openFiles, openFolder, openCurrentFolder }

class GalleryActionsMenu extends StatelessWidget {
  final String tooltip;
  final String openFolderLabel;
  final String openFilesLabel;
  final String openCurrentFolderLabel;
  final String recentItemsTitle;
  final String noRecentItemsLabel;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;
  final List<RecentOpenItem> recentOpenItems;
  final ValueChanged<RecentOpenItem> onRecentOpenItemSelected;

  const GalleryActionsMenu({
    super.key,
    required this.tooltip,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.recentItemsTitle,
    required this.noRecentItemsLabel,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
    required this.recentOpenItems,
    required this.onRecentOpenItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopPopupMenuButton<GalleryAction>(
      tooltip: tooltip,
      offset: const Offset(0, 36),
      onSelected: (action) {
        switch (action) {
          case GalleryAction.openFiles:
            onOpenFiles();
            break;
          case GalleryAction.openFolder:
            onOpenFolder();
            break;
          case GalleryAction.openCurrentFolder:
            onOpenCurrentFolder?.call();
            break;
        }
      },
      itemBuilder: (context) => [
        desktopPopupMenuItem<GalleryAction>(
          value: GalleryAction.openFiles,
          icon: Icons.file_open_outlined,
          label: openFilesLabel,
        ),
        desktopPopupMenuItem<GalleryAction>(
          value: GalleryAction.openFolder,
          icon: Icons.folder_open_outlined,
          label: openFolderLabel,
        ),
        desktopPopupMenuItem<GalleryAction>(
          value: GalleryAction.openCurrentFolder,
          enabled: onOpenCurrentFolder != null,
          icon: Icons.open_in_new,
          label: openCurrentFolderLabel,
        ),
        const PopupMenuDivider(height: 12),
        PopupMenuItem<GalleryAction>(
          enabled: false,
          height: 36,
          padding: EdgeInsets.zero,
          child: _RecentOpenItemsSubmenu(
            title: recentItemsTitle,
            emptyLabel: noRecentItemsLabel,
            items: recentOpenItems,
            onSelected: (item) {
              Navigator.pop(context);
              onRecentOpenItemSelected(item);
            },
          ),
        ),
      ],
      child: const DesktopPopupMenuTrigger(
        icon: Icons.more_vert,
      ),
    );
  }
}

class _RecentOpenItemsSubmenu extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<RecentOpenItem> items;
  final ValueChanged<RecentOpenItem> onSelected;

  const _RecentOpenItemsSubmenu({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DesktopPopupMenuButton<RecentOpenItem>(
      key: const ValueKey('recent-open-submenu'),
      tooltip: title,
      offset: const Offset(196, 0),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (items.isEmpty)
          PopupMenuItem<RecentOpenItem>(
            enabled: false,
            height: 36,
            padding: EdgeInsets.zero,
            child: _RecentOpenItemsMenuContent(
              icon: Icons.history,
              label: emptyLabel,
              enabled: false,
            ),
          )
        else
          ...items.map(
            (item) => desktopPopupMenuItem<RecentOpenItem>(
              value: item,
              icon: item.isDirectory
                  ? Icons.folder_outlined
                  : Icons.insert_drive_file_outlined,
              label: item.path,
            ),
          ),
      ],
      child: _RecentOpenItemsMenuContent(
        icon: Icons.history,
        label: title,
        trailingIcon: Icons.chevron_right,
      ),
    );
  }
}

class _RecentOpenItemsMenuContent extends StatelessWidget {
  final IconData icon;
  final String label;
  final IconData? trailingIcon;
  final bool enabled;

  const _RecentOpenItemsMenuContent({
    required this.icon,
    required this.label,
    this.trailingIcon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        enabled ? RawViewerColors.text : RawViewerColors.mutedBorder;
    final iconColor =
        enabled ? RawViewerColors.mutedText : RawViewerColors.mutedBorder;

    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3)),
      child: Row(
        children: [
          SizedBox(width: 22, child: Icon(icon, size: 17, color: iconColor)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 8),
            Icon(trailingIcon, size: 17, color: iconColor),
          ],
        ],
      ),
    );
  }
}

class ThumbnailSizeControls extends StatelessWidget {
  final String largerThumbnailsTooltip;
  final String smallerThumbnailsTooltip;
  final VoidCallback? onDecreaseThumbnailSize;
  final VoidCallback? onIncreaseThumbnailSize;

  const ThumbnailSizeControls({
    super.key,
    required this.largerThumbnailsTooltip,
    required this.smallerThumbnailsTooltip,
    required this.onDecreaseThumbnailSize,
    required this.onIncreaseThumbnailSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DesktopIconButton(
          icon: Icons.zoom_in,
          tooltip: largerThumbnailsTooltip,
          onPressed: onDecreaseThumbnailSize,
        ),
        const SizedBox(height: 4),
        DesktopIconButton(
          icon: Icons.zoom_out,
          tooltip: smallerThumbnailsTooltip,
          onPressed: onIncreaseThumbnailSize,
        ),
      ],
    );
  }
}
