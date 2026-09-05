import 'package:flutter/material.dart';

import '../../media_filter.dart';
import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';

class DesktopCommandBar extends StatelessWidget {
  final String title;
  final String openFolderLabel;
  final String openFilesLabel;
  final String openCurrentFolderLabel;
  final String moreActionsTooltip;
  final String settingsTooltip;
  final MediaFilter selectedMediaFilter;
  final int adaptiveCount;
  final int rawCount;
  final int imageCount;
  final ValueChanged<MediaFilter> onMediaFilterSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;

  const DesktopCommandBar({
    super.key,
    required this.title,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.moreActionsTooltip,
    required this.settingsTooltip,
    required this.selectedMediaFilter,
    required this.adaptiveCount,
    required this.rawCount,
    required this.imageCount,
    required this.onMediaFilterSelected,
    required this.onOpenSettings,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
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
                onOpenFiles: onOpenFiles,
                onOpenFolder: onOpenFolder,
                onOpenCurrentFolder: onOpenCurrentFolder,
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
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final VoidCallback? onOpenCurrentFolder;

  const GalleryActionsMenu({
    super.key,
    required this.tooltip,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.openCurrentFolderLabel,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.onOpenCurrentFolder,
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
        desktopPopupMenuItem(
          value: GalleryAction.openFiles,
          icon: Icons.file_open_outlined,
          label: openFilesLabel,
        ),
        desktopPopupMenuItem(
          value: GalleryAction.openFolder,
          icon: Icons.folder_open_outlined,
          label: openFolderLabel,
        ),
        desktopPopupMenuItem(
          value: GalleryAction.openCurrentFolder,
          enabled: onOpenCurrentFolder != null,
          icon: Icons.open_in_new,
          label: openCurrentFolderLabel,
        ),
      ],
      child: const DesktopPopupMenuTrigger(
        icon: Icons.more_vert,
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
