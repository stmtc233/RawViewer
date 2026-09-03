import 'package:path/path.dart' as path_utils;

enum MediaKind { raw, bitmap }

class MediaFile {
  final String path;
  final MediaKind kind;

  const MediaFile({required this.path, required this.kind});

  bool get isRaw => kind == MediaKind.raw;

  bool get isJpeg {
    final extension = path_utils.extension(path).toLowerCase();
    return extension == '.jpg' || extension == '.jpeg';
  }
}

class MediaGroup {
  final MediaFile primary;
  final MediaFile? pairedJpeg;

  const MediaGroup({required this.primary, this.pairedJpeg});

  bool get isRaw => primary.isRaw;
  bool get hasPairedJpeg => pairedJpeg != null;
}

List<MediaGroup> buildAdaptiveMediaGroups(Iterable<MediaFile> files) {
  final orderedFiles = List<MediaFile>.of(files);
  final jpegByStem = <String, List<MediaFile>>{};

  for (final file in orderedFiles) {
    if (!file.isJpeg) {
      continue;
    }
    jpegByStem.putIfAbsent(_pairingStem(file.path), () => []).add(file);
  }

  final pairedJpegsByRawPath = <String, MediaFile>{};
  for (final file in orderedFiles) {
    if (!file.isRaw) {
      continue;
    }
    final pairedJpeg = _preferredJpeg(jpegByStem[_pairingStem(file.path)]);
    if (pairedJpeg != null) {
      pairedJpegsByRawPath[file.path] = pairedJpeg;
    }
  }
  final pairedJpegPaths =
      pairedJpegsByRawPath.values.map((file) => file.path).toSet();

  return [
    for (final file in orderedFiles)
      if (file.isRaw)
        MediaGroup(
          primary: file,
          pairedJpeg: pairedJpegsByRawPath[file.path],
        )
      else if (!pairedJpegPaths.contains(file.path))
        MediaGroup(primary: file),
  ];
}

MediaFile? _preferredJpeg(List<MediaFile>? candidates) {
  if (candidates == null || candidates.isEmpty) {
    return null;
  }
  for (final candidate in candidates) {
    if (path_utils.extension(candidate.path).toLowerCase() == '.jpg') {
      return candidate;
    }
  }
  return candidates.first;
}

String _pairingStem(String filePath) {
  return path_utils
      .withoutExtension(path_utils.normalize(filePath))
      .toLowerCase();
}
