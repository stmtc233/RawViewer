import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'core/concurrency.dart';
import 'l10n/app_localizations.dart';
import 'media_group.dart';
import 'ui/desktop_controls.dart';

enum MediaSortOrder {
  nameAscending,
  nameDescending,
  capturedNewest,
  capturedOldest,
  modifiedNewest,
  modifiedOldest,
  ratingDescending,
  ratingAscending;

  bool get isRating => this == ratingDescending || this == ratingAscending;
}

const defaultMediaSortOrder = MediaSortOrder.nameAscending;

// Per-file metadata loads overlap instead of running one file at a time.
const int _concurrentSortLoads = 8;

typedef CapturedAtLoader = Future<DateTime> Function(String filePath);

/// Returns a new file list ordered according to [sortOrder].
///
/// File names are used as a deterministic tiebreaker for equal or unreadable
/// timestamps, keeping the grid stable across rebuilds. Capture-time sorting
/// requires [loadCapturedAt], which should fall back to the modified time when
/// the file has no readable capture timestamp.
Future<List<MediaFile>> sortMediaFiles(
    Iterable<MediaFile> files, MediaSortOrder sortOrder,
    {CapturedAtLoader? loadCapturedAt,
    Future<int?> Function(String filePath)? loadRating,
    bool Function()? isCancelled}) async {
  final sortedFiles = List<MediaFile>.of(files);
  switch (sortOrder) {
    case MediaSortOrder.nameAscending:
      return _sortWithKeys(sortedFiles);
    case MediaSortOrder.nameDescending:
      return (await _sortWithKeys(sortedFiles))
          .reversed
          .toList(growable: false);
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
        isCancelled: isCancelled,
      );
    case MediaSortOrder.modifiedNewest:
    case MediaSortOrder.modifiedOldest:
      return _sortByTime(
        sortedFiles,
        newestFirst: sortOrder == MediaSortOrder.modifiedNewest,
        loadTime: (file) => File(file.path).lastModified(),
        isCancelled: isCancelled,
      );
    case MediaSortOrder.ratingDescending:
    case MediaSortOrder.ratingAscending:
      if (loadRating == null) {
        throw ArgumentError('Rating sorting requires a loadRating callback.');
      }
      final ratings = <String, int>{};
      await forEachConcurrently(sortedFiles, _concurrentSortLoads,
          (file) async {
        try {
          final rating = await loadRating(file.path);
          ratings[file.path] =
              rating != null && rating >= 0 && rating <= 5 ? rating : 0;
        } catch (_) {
          ratings[file.path] = 0;
        }
      }, isCancelled: isCancelled);
      if (isCancelled?.call() ?? false) return sortedFiles;
      return _sortWithKeys(sortedFiles,
          values: ratings,
          descending: sortOrder == MediaSortOrder.ratingDescending);
  }
}

Future<List<MediaFile>> _sortByTime(
  List<MediaFile> files, {
  required bool newestFirst,
  required Future<DateTime> Function(MediaFile file) loadTime,
  bool Function()? isCancelled,
}) async {
  final timestamps = <String, int>{};
  await forEachConcurrently(files, _concurrentSortLoads, (file) async {
    try {
      timestamps[file.path] = (await loadTime(file)).microsecondsSinceEpoch;
    } on FileSystemException {
      timestamps[file.path] = 0;
    }
  }, isCancelled: isCancelled);
  if (isCancelled?.call() ?? false) return files;
  return _sortWithKeys(files, values: timestamps, descending: newestFirst);
}

Future<List<MediaFile>> _sortWithKeys(List<MediaFile> files,
    {Map<String, int>? values, bool descending = false}) async {
  // Only send data to the isolate; metadata callbacks can own widget state.
  if (files.length >= 256) {
    return Isolate.run(() => _sortWithKeysSync(files, values, descending));
  }
  return _sortWithKeysSync(files, values, descending);
}

List<MediaFile> _sortWithKeysSync(
    List<MediaFile> files, Map<String, int>? values, bool descending) {
  // Compute path keys once, instead of allocating them O(n log n) times.
  final names = {
    for (final file in files) file.path: path.basename(file.path).toLowerCase(),
  };
  final paths = {for (final file in files) file.path: file.path.toLowerCase()};
  files.sort((a, b) {
    final comparison = (values?[a.path] ?? 0).compareTo(values?[b.path] ?? 0);
    if (comparison != 0) return descending ? -comparison : comparison;
    final byName = names[a.path]!.compareTo(names[b.path]!);
    return byName != 0 ? byName : paths[a.path]!.compareTo(paths[b.path]!);
  });
  return files;
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
        desktopPopupMenuItem(
          value: MediaSortOrder.ratingDescending,
          icon: Icons.star_outline,
          selected: selectedSortOrder == MediaSortOrder.ratingDescending,
          label: l10n.mediaSortRatingDescending,
        ),
        desktopPopupMenuItem(
          value: MediaSortOrder.ratingAscending,
          icon: Icons.star_outline,
          selected: selectedSortOrder == MediaSortOrder.ratingAscending,
          label: l10n.mediaSortRatingAscending,
        ),
      ],
      child: const DesktopPopupMenuTrigger(icon: Icons.sort),
    );
  }
}
