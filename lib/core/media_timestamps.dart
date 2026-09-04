import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:intl/intl.dart';

import '../settings_page.dart';

final DateFormat _timestampFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

class MediaTimestampInfo {
  final DateTime? capturedAt;
  final DateTime modifiedAt;

  const MediaTimestampInfo({
    required this.capturedAt,
    required this.modifiedAt,
  });

  DateTime getDisplayTime(TimeDisplaySource source) {
    switch (source) {
      case TimeDisplaySource.capturedAt:
        return capturedAt ?? modifiedAt;
      case TimeDisplaySource.modifiedAt:
        return modifiedAt;
    }
  }

  String format(TimeDisplaySource source) {
    return _timestampFormatter.format(getDisplayTime(source));
  }
}

class TimestampRepository {
  // Bounded so browsing a very large directory cannot grow this without limit.
  static const int _maxEntries = 2048;
  final LinkedHashMap<String, Future<MediaTimestampInfo>> _futureCache =
      LinkedHashMap<String, Future<MediaTimestampInfo>>();

  Future<MediaTimestampInfo> load(String filePath) {
    final existing = _futureCache.remove(filePath);
    if (existing != null) {
      _futureCache[filePath] = existing; // Refresh recency.
      return existing;
    }

    final future = _readTimestampInfo(filePath);
    _futureCache[filePath] = future;
    while (_futureCache.length > _maxEntries) {
      _futureCache.remove(_futureCache.keys.first);
    }
    return future;
  }

  void clear() {
    _futureCache.clear();
  }

  // Read only the first portion of the file for EXIF parsing to avoid
  // loading entire multi-MB RAW files into memory (which causes OOM crashes
  // when many files are opened concurrently).
  static const int _exifReadSize = 128 * 1024; // 128 KB

  Future<MediaTimestampInfo> _readTimestampInfo(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    final modifiedAt = stat.modified;
    DateTime? capturedAt;

    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final length = await raf.length();
        final readLength = length < _exifReadSize ? length : _exifReadSize;
        final bytes = await raf.read(readLength);
        capturedAt = await _parseCapturedAtFromBytes(bytes);
      } finally {
        await raf.close();
      }
    } catch (_) {
      capturedAt = null;
    }

    return MediaTimestampInfo(capturedAt: capturedAt, modifiedAt: modifiedAt);
  }
}

// Runs on a helper isolate: EXIF parsing is pure CPU work and parsing it inline
// stutters the grid when many tiles resolve their timestamps at once.
Future<DateTime?> _parseCapturedAtFromBytes(Uint8List bytes) {
  return Isolate.run(() => _parseCapturedAtFromBytesSync(bytes));
}

Future<DateTime?> _parseCapturedAtFromBytesSync(Uint8List bytes) async {
  try {
    final data = await readExifFromBytes(bytes);
    final rawValue = data['Image DateTime']?.printable ??
        data['EXIF DateTimeOriginal']?.printable ??
        data['EXIF DateTimeDigitized']?.printable;
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }
    return _parseExifDateTime(rawValue);
  } catch (_) {
    return null;
  }
}

DateTime? _parseExifDateTime(String value) {
  final normalized = value.trim();
  final exifMatch = RegExp(
    r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(normalized);
  if (exifMatch != null) {
    return DateTime(
      int.parse(exifMatch.group(1)!),
      int.parse(exifMatch.group(2)!),
      int.parse(exifMatch.group(3)!),
      int.parse(exifMatch.group(4)!),
      int.parse(exifMatch.group(5)!),
      int.parse(exifMatch.group(6)!),
    );
  }
  return DateTime.tryParse(normalized);
}
