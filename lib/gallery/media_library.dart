import 'dart:io';

import 'package:path/path.dart' as path;

import '../core/media_types.dart';
import '../media_group.dart';

/// Scans [directoryPath] for supported media files, sorted by name.
List<MediaFile> listMediaFilesInDirectory(String directoryPath) {
  return Directory(directoryPath)
      .listSync()
      .whereType<File>()
      .map((file) => mediaFileFromPath(file.path))
      .whereType<MediaFile>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

/// Filters [files] down to a supported media file, or null when the extension
/// is not recognised.
///
/// The returned path is normalized and absolute so callers can compare entries
/// without worrying about relative / canonical differences.
MediaFile? mediaFileFromPath(String filePath) {
  final normalizedPath = path.normalize(path.absolute(filePath));
  final extension = path.extension(normalizedPath).toLowerCase();
  if (rawExtensions.contains(extension)) {
    return MediaFile(path: normalizedPath, kind: MediaKind.raw);
  }
  if (bitmapExtensions.contains(extension)) {
    return MediaFile(path: normalizedPath, kind: MediaKind.bitmap);
  }
  return null;
}

/// Removes duplicates from [files] by normalized absolute path, preserving
/// first-occurrence order.
List<MediaFile> deduplicateMediaFiles(Iterable<MediaFile> files) {
  final seen = <String>{};
  final result = <MediaFile>[];

  for (final mediaFile in files) {
    final normalizedPath = path.normalize(path.absolute(mediaFile.path));
    if (seen.add(normalizedPath)) {
      result.add(MediaFile(path: normalizedPath, kind: mediaFile.kind));
    }
  }

  return result;
}
