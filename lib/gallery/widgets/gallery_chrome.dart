import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/desktop_controls.dart';

class EmptyGallery extends StatelessWidget {
  final String message;
  final String openFolderLabel;
  final String openFilesLabel;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenFolder;

  const EmptyGallery({
    super.key,
    required this.message,
    required this.openFolderLabel,
    required this.openFilesLabel,
    required this.onOpenFiles,
    required this.onOpenFolder,
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
          ],
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

