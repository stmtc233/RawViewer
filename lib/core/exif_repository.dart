import 'dart:io';
import 'dart:isolate';

import 'package:exif/exif.dart';

int? parseExifRating(String? value) {
  final rating = int.tryParse(value?.trim() ?? '');
  return rating != null && rating >= 0 && rating <= 5 ? rating : null;
}

class ExifMetadata {
  final int? fileSize;
  final DateTime? modifiedAt;
  final Map<String, String> tags;
  final Map<String, double> numericValues;
  final bool readFailed;

  const ExifMetadata({
    this.fileSize,
    this.modifiedAt,
    this.tags = const {},
    this.numericValues = const {},
    this.readFailed = false,
  });
}

class ExifRepository {
  final _cache = <String, Future<ExifMetadata>>{};
  Future<void> _pending = Future<void>.value();

  Future<ExifMetadata> load(String filePath) {
    final cached = _cache.remove(filePath);
    if (cached != null) {
      _cache[filePath] = cached;
      return cached;
    }

    // Serialize reads so navigation never starts a pool of metadata isolates.
    final future = _pending.then((_) => Isolate.run(() => _readExif(filePath)));
    _pending = future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _cache[filePath] = future;
    while (_cache.length > 16) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }
}

Future<ExifMetadata> _readExif(String filePath) async {
  int? fileSize;
  DateTime? modifiedAt;
  try {
    final file = File(filePath);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return const ExifMetadata(readFailed: true);
    }
    fileSize = stat.size;
    modifiedAt = stat.modified;
    // Seek through the file instead of reading a whole RAW or truncating its
    // header. Some cameras store metadata well beyond the first 128 KB.
    final tags = await readExifFromFile(file, details: true);
    return ExifMetadata(
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      tags: Map.unmodifiable({
        for (final entry in tags.entries)
          if (entry.value.printable.trim().isNotEmpty)
            entry.key: entry.value.printable.replaceAll('\u0000', '').trim(),
      }),
      numericValues: Map.unmodifiable({
        for (final entry in tags.entries)
          if (_numericValue(entry.value.values) case final double value)
            entry.key: value,
      }),
    );
  } catch (_) {
    return ExifMetadata(
      fileSize: fileSize,
      modifiedAt: modifiedAt,
      readFailed: true,
    );
  }
}

double? _numericValue(IfdValues values) {
  if (values.length != 1) return null;
  if (values is IfdRatios) {
    final ratio = values.ratios.single;
    return ratio.denominator == 0 ? null : ratio.toDouble();
  }
  if (values is IfdInts) return values.ints.single.toDouble();
  return null;
}
