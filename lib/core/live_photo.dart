import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as paths;
import 'package:xml/xml.dart';

/// A companion movie, or a bounded movie range inside a Motion Photo.
class LivePhotoSource {
  final String path;
  final int offset;
  final int length;

  const LivePhotoSource(this.path, {this.offset = 0, required this.length});

  bool get isEmbedded => offset > 0;
}

Future<LivePhotoSource?> findLivePhoto(String imagePath) {
  if (!['.jpg', '.jpeg', '.heic', '.heif']
      .contains(paths.extension(imagePath).toLowerCase())) {
    return Future.value();
  }
  return Isolate.run(() => _findLivePhoto(imagePath));
}

LivePhotoSource? _findLivePhoto(String imagePath) {
  try {
    final extension = paths.extension(imagePath).toLowerCase();
    if (!['.jpg', '.jpeg', '.heic', '.heif'].contains(extension)) return null;
    final image = File(imagePath);
    if (!image.existsSync()) return null;
    final stem = paths.basenameWithoutExtension(imagePath).toLowerCase();
    final companions = image.parent
        .listSync()
        .whereType<File>()
        .where((file) =>
            paths.extension(file.path).toLowerCase() == '.mov' &&
            paths.basenameWithoutExtension(file.path).toLowerCase() == stem)
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final movie in companions) {
      final handle = movie.openSync();
      try {
        final length = handle.lengthSync();
        if (_isMovie(handle, 0, length)) {
          return LivePhotoSource(movie.path, length: length);
        }
      } finally {
        handle.closeSync();
      }
    }
    if (extension != '.jpg' && extension != '.jpeg') return null;
    final handle = image.openSync();
    try {
      final fileLength = handle.lengthSync();
      if (handle.readByteSync() != 0xff || handle.readByteSync() != 0xd8) {
        return null;
      }
      // Read JPEG metadata segments only; never scan the image or movie payload.
      while (handle.positionSync() < fileLength) {
        if (handle.readByteSync() != 0xff) return null;
        var marker = handle.readByteSync();
        while (marker == 0xff) {
          marker = handle.readByteSync();
        }
        if (marker < 0 || marker == 0xda || marker == 0xd9) return null;
        if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
        final high = handle.readByteSync();
        final low = handle.readByteSync();
        if (high < 0 || low < 0) return null;
        final size = high * 256 + low - 2;
        final end = handle.positionSync() + size;
        if (size < 0 || end > fileLength) return null;
        if (marker == 0xe1) {
          final bytes = handle.readSync(size);
          const prefix = 'http://ns.adobe.com/xap/1.0/\u0000';
          if (bytes.length >= prefix.length &&
              latin1.decode(bytes.sublist(0, prefix.length)) == prefix) {
            final range = motionPhotoRangeFromXmp(
              utf8.decode(bytes.sublist(prefix.length), allowMalformed: true),
              fileLength,
            );
            if (range != null &&
                range.offset >= end &&
                _isMovie(handle, range.offset, range.length)) {
              return LivePhotoSource(imagePath,
                  offset: range.offset, length: range.length);
            }
          }
        }
        handle.setPositionSync(end);
      }
    } finally {
      handle.closeSync();
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

bool _isMovie(RandomAccessFile file, int offset, int length) {
  if (length < 16) return false;
  file.setPositionSync(offset);
  final bytes = file.readSync(12);
  if (bytes.length != 12 || latin1.decode(bytes.sublist(4, 8)) != 'ftyp') {
    return false;
  }
  final boxSize =
      bytes[0] * 0x1000000 + bytes[1] * 0x10000 + bytes[2] * 0x100 + bytes[3];
  return boxSize >= 16 && boxSize <= length;
}

const _cameraNamespace = 'http://ns.google.com/photos/1.0/camera/';
const _containerNamespace = 'http://ns.google.com/photos/1.0/container/';
const _itemNamespace = 'http://ns.google.com/photos/1.0/container/item/';

/// Google Motion Photo v1 (tail offset) and v2 (container directory).
({int offset, int length})? motionPhotoRangeFromXmp(
    String xmp, int fileLength) {
  try {
    final document = XmlDocument.parse(xmp);
    String? property(XmlElement element, String name, String namespace) {
      return element.getAttribute(name, namespaceUri: namespace) ??
          element.getElement(name, namespaceUri: namespace)?.innerText;
    }

    final elements = document.descendants.whereType<XmlElement>().toList();
    final enabled = elements.any((element) =>
        property(element, 'MotionPhoto', _cameraNamespace) == '1' ||
        property(element, 'MicroVideo', _cameraNamespace) == '1');
    if (!enabled) return null;
    for (final directory in elements.where((element) =>
        element.name.local == 'Directory' &&
        element.namespaceUri == _containerNamespace)) {
      final items = directory.descendants.whereType<XmlElement>().where(
          (element) => property(element, 'Semantic', _itemNamespace) != null);
      var end = fileLength;
      for (final item in items.toList().reversed) {
        final length =
            int.tryParse(property(item, 'Length', _itemNamespace) ?? '') ?? 0;
        final padding =
            int.tryParse(property(item, 'Padding', _itemNamespace) ?? '0');
        if (length < 0 || padding == null || padding < 0) return null;
        end -= padding;
        final start = end - length;
        if (start < 0) return null;
        if (property(item, 'Semantic', _itemNamespace) == 'MotionPhoto' &&
            property(item, 'Mime', _itemNamespace) == 'video/mp4') {
          if (length < 16 || start <= 0) return null;
          return (offset: start, length: length);
        }
        end = start;
      }
    }
    for (final element in elements) {
      final offset = int.tryParse(
          property(element, 'MicroVideoOffset', _cameraNamespace) ?? '');
      if (offset != null && offset >= 16 && offset < fileLength) {
        return (offset: fileLength - offset, length: offset);
      }
    }
  } on XmlException {
    return null;
  }
  return null;
}

/// Owns only its temporary extraction; companion files are never removed.
class LivePhotoPlaybackFile {
  final String path;
  final Directory? _temporaryDirectory;

  LivePhotoPlaybackFile._(this.path, this._temporaryDirectory);

  static Future<LivePhotoPlaybackFile> prepare(LivePhotoSource source) async {
    if (!source.isEmbedded) return LivePhotoPlaybackFile._(source.path, null);
    final directory = await Directory.systemTemp.createTemp('rawviewer-live-');
    try {
      final file = File(paths.join(directory.path, 'motion.mp4'));
      final input = File(source.path);
      if (source.offset + source.length > await input.length()) {
        throw const FileSystemException('Motion Photo was truncated');
      }
      await input
          .openRead(source.offset, source.offset + source.length)
          .pipe(file.openWrite());
      return LivePhotoPlaybackFile._(file.path, directory);
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    final directory = _temporaryDirectory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}
