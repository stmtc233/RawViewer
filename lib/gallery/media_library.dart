import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as path;

import '../core/media_types.dart';
import '../media_group.dart';

/// Scans [directoryPath] for supported media files, sorted by name.
///
/// Runs on a helper isolate: listing a network share or a folder with tens of
/// thousands of entries can take seconds, which would otherwise freeze the UI
/// for that long. A [FileSystemException] still reaches the caller.
Future<List<MediaFile>> listMediaFilesInDirectory(String directoryPath) =>
    Isolate.run(() => _listMediaFilesInDirectorySync(directoryPath));

/// Streams bounded batches without waiting for a slow directory to finish.
/// Cancelling the subscription terminates the scanner, including its pending
/// directory listing. File contents are never opened during enumeration.
Stream<List<MediaFile>> scanMediaFilesInDirectory(String directoryPath) {
  late final StreamController<List<MediaFile>> controller;
  ReceivePort? messages;
  Isolate? scanner;
  var stopped = false;
  void stop() {
    stopped = true;
    messages?.close();
    scanner?.kill(priority: Isolate.immediate);
  }

  Future<void> start() async {
    final port = messages = ReceivePort();
    port.listen((message) {
      if (stopped) return;
      if (message == null) {
        unawaited(controller.close());
        stop();
        return;
      }
      if (message is List<MediaFile>) {
        controller.add(message);
      } else if (message is FileSystemException) {
        controller.addError(message);
      } else {
        controller.addError(StateError('Directory scanner failed: $message'));
      }
    });
    try {
      final isolate = await Isolate.spawn(
          _scanDirectory, (directoryPath, port.sendPort),
          onError: port.sendPort, onExit: port.sendPort);
      scanner = isolate;
      if (stopped) isolate.kill(priority: Isolate.immediate);
    } catch (error, stack) {
      if (!stopped) {
        controller.addError(error, stack);
        unawaited(controller.close());
        stop();
      }
    }
  }

  controller =
      StreamController<List<MediaFile>>(onListen: start, onCancel: stop);
  return controller.stream;
}

Future<void> _scanDirectory((String, SendPort) request) async {
  final (directoryPath, reply) = request;
  var batch = <MediaFile>[];
  final elapsed = Stopwatch()..start();
  try {
    await for (final entry in Directory(directoryPath).list()) {
      if (entry is File) {
        final file = mediaFileFromPath(entry.path);
        if (file != null) batch.add(file);
      }
      if (batch.isNotEmpty &&
          (batch.length >= 128 || elapsed.elapsedMilliseconds >= 100)) {
        reply.send(batch);
        batch = <MediaFile>[];
        elapsed.reset();
      }
    }
    if (batch.isNotEmpty) reply.send(batch);
  } on FileSystemException catch (error) {
    if (batch.isNotEmpty) reply.send(batch);
    reply.send(error);
  } catch (error, stack) {
    reply.send(['$error', '$stack']);
  } finally {
    reply.send(null);
  }
}

List<MediaFile> _listMediaFilesInDirectorySync(String directoryPath) {
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
