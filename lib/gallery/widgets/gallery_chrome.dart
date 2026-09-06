import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../../core/preferences_repository.dart';
import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';

class EmptyGallery extends StatelessWidget {
  final String message;
  final String openFolderLabel;
  final String openFilesLabel;
  final String recentItemsTitle;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;
  final List<RecentOpenItem> recentOpenItems;
  final ValueChanged<RecentOpenItem> onRecentOpenItemSelected;

  const EmptyGallery({
    super.key,
    required this.message,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.recentItemsTitle,
    required this.onOpenFiles,
    required this.onOpenFolder,
    required this.recentOpenItems,
    required this.onRecentOpenItemSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: RawViewerColors.surface,
                border: Border.all(color: RawViewerColors.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: RawViewerColors.mutedText,
                size: 26,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RawViewerColors.mutedText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                DesktopCommandButton(
                  icon: Icons.folder_open_outlined,
                  label: openFolderLabel,
                  onPressed: onOpenFolder,
                  emphasized: true,
                ),
                DesktopCommandButton(
                  icon: Icons.file_open_outlined,
                  label: openFilesLabel,
                  onPressed: onOpenFiles,
                ),
              ],
            ),
            if (recentOpenItems.isNotEmpty) ...[
              const SizedBox(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  recentItemsTitle,
                  style: const TextStyle(
                    color: RawViewerColors.mutedText,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              ...recentOpenItems.take(5).map(
                    (item) => _RecentOpenItemButton(
                      item: item,
                      onPressed: () => onRecentOpenItemSelected(item),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecentOpenItemButton extends StatelessWidget {
  final RecentOpenItem item;
  final VoidCallback onPressed;

  const _RecentOpenItemButton({
    required this.item,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onPressed,
        hoverColor: RawViewerColors.raisedSurface,
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              Icon(
                item.isDirectory
                    ? Icons.folder_outlined
                    : Icons.insert_drive_file_outlined,
                size: 18,
                color: RawViewerColors.mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      path.basename(item.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RawViewerColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      item.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RawViewerColors.mutedText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GalleryStatusBar extends StatelessWidget {
  final String itemCountLabel;
  final String gridColumnsLabel;

  const GalleryStatusBar({
    super.key,
    required this.itemCountLabel,
    required this.gridColumnsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: RawViewerColors.surface,
        border: Border(top: BorderSide(color: RawViewerColors.mutedBorder)),
      ),
      child: Row(
        children: [
          Text(
            itemCountLabel,
            style: const TextStyle(
              color: RawViewerColors.mutedText,
              fontSize: 11,
            ),
          ),
          const Spacer(),
          Text(
            gridColumnsLabel,
            style: const TextStyle(
              color: RawViewerColors.mutedText,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
