import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'l10n/app_localizations.dart';
import 'media_group.dart';
import 'ui/desktop_controls.dart';

enum MediaSortOrder {
  nameAscending,
  nameDescending,
  capturedNewest,
  capturedOldest,
  modifiedNewest,
  modifiedOldest;
}

const defaultMediaSortOrder = MediaSortOrder.nameAscending;

typedef CapturedAtLoader = Future<DateTime> Function(String filePath);

/// Returns a new file list ordered according to [sortOrder].
///
/// File names are used as a deterministic tiebreaker for equal or unreadable
/// timestamps, keeping the grid stable across rebuilds. Capture-time sorting
/// requires [loadCapturedAt], which should fall back to the modified time when
/// the file has no readable capture timestamp.
Future<List<MediaFile>> sortMediaFiles(
    Iterable<MediaFile> files, MediaSortOrder sortOrder,
    {CapturedAtLoader? loadCapturedAt}) async {
  final sortedFiles = List<MediaFile>.of(files);
  switch (sortOrder) {
    case MediaSortOrder.nameAscending:
      sortedFiles.sort(_compareByName);
      return sortedFiles;
    case MediaSortOrder.nameDescending:
      sortedFiles.sort(_compareByName);
      return sortedFiles.reversed.toList(growable: false);
    case MediaSortOrder.capturedNewest:
    case MediaSortOrder.capturedOldest:
      if (loadCapturedAt == null) {
        throw ArgumentError(
          'Capture-time sorting requires a loadCapturedAt callback.',
        );
      }
      return _sortByTime(
        sortedFiles,
        newestFirst: sortOrder == MediaSortOrder.capturedNewest,
        loadTime: (file) => loadCapturedAt(file.path),
      );
    case MediaSortOrder.modifiedNewest:
    case MediaSortOrder.modifiedOldest:
      return _sortByTime(
        sortedFiles,
        newestFirst: sortOrder == MediaSortOrder.modifiedNewest,
        loadTime: (file) => File(file.path).lastModified(),
      );
  }
}

Future<List<MediaFile>> _sortByTime(
  List<MediaFile> files, {
  required bool newestFirst,
  required Future<DateTime> Function(MediaFile file) loadTime,
}) async {
  final timestamps = <String, DateTime>{};
  for (final file in files) {
    try {
      timestamps[file.path] = await loadTime(file);
    } on FileSystemException {
      timestamps[file.path] = DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  files.sort((a, b) {
    final comparison = timestamps[a.path]!.compareTo(timestamps[b.path]!);
    if (comparison == 0) {
      return _compareByName(a, b);
    }
    return newestFirst ? -comparison : comparison;
  });
  return files;
}

int _compareByName(MediaFile a, MediaFile b) {
  final aName = path.basename(a.path).toLowerCase();
  final bName = path.basename(b.path).toLowerCase();
  final nameComparison = aName.compareTo(bName);
  if (nameComparison != 0) {
    return nameComparison;
  }
  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
}

class MediaSortButton extends StatelessWidget {
  final MediaSortOrder selectedSortOrder;
  final bool enabled;
  final ValueChanged<MediaSortOrder> onSelected;

  const MediaSortButton({
    super.key,
    required this.selectedSortOrder,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DesktopPopupMenuButton<MediaSortOrder>(
      enabled: enabled,
      tooltip: l10n.mediaSortTooltip,
      onSelected: onSelected,
      itemBuilder: (context) => [
        desktopPopupMenuItem(
          value: MediaSortOrder.nameAscending,
          icon: Icons.sort_by_alpha,
          selected: selectedSortOrder == MediaSortOrder.nameAscending,
          label: l10n.mediaSortNameAscending,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.nameDescending,
          icon: Icons.sort_by_alpha,
          selected: selectedSortOrder == MediaSortOrder.nameDescending,
          label: l10n.mediaSortNameDescending,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.capturedNewest,
          icon: Icons.photo_camera_outlined,
          selected: selectedSortOrder == MediaSortOrder.capturedNewest,
          label: l10n.mediaSortCapturedNewest,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.capturedOldest,
          icon: Icons.photo_camera_outlined,
          selected: selectedSortOrder == MediaSortOrder.capturedOldest,
          label: l10n.mediaSortCapturedOldest,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.modifiedNewest,
          icon: Icons.schedule,
          selected: selectedSortOrder == MediaSortOrder.modifiedNewest,
          label: l10n.mediaSortModifiedNewest,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.modifiedOldest,
          icon: Icons.schedule,
          selected: selectedSortOrder == MediaSortOrder.modifiedOldest,
          label: l10n.mediaSortModifiedOldest,
        ),
      ],
      child: const DesktopPopupMenuTrigger(icon: Icons.sort),
    );
  }
}
