import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_types.dart';
import 'package:rawviewer/gallery/media_library.dart';
import 'package:rawviewer/media_group.dart';

void main() {
  group('mediaFileFromPath', () {
    test('recognises every supported RAW extension as raw', () {
      for (final ext in rawExtensions) {
        final result = mediaFileFromPath('/photos/shot$ext');
        expect(result, isNotNull, reason: 'expected $ext to be recognised');
        expect(result!.isRaw, isTrue, reason: '$ext should be raw');
      }
    });

    test('recognises every supported bitmap extension as bitmap', () {
      for (final ext in bitmapExtensions) {
        final result = mediaFileFromPath('/photos/shot$ext');
        expect(result, isNotNull, reason: 'expected $ext to be recognised');
        expect(result!.isRaw, isFalse, reason: '$ext should be bitmap');
      }
    });

    test('recognises the formats added beyond the original set', () {
      for (final ext in ['.crw', '.nrw', '.pef', '.rwl', '.3fr', '.iiq']) {
        expect(mediaFileFromPath('/photos/shot$ext')?.isRaw, isTrue,
            reason: '$ext should be raw');
      }
      for (final ext in ['.gif', '.bmp']) {
        expect(mediaFileFromPath('/photos/shot$ext')?.isRaw, isFalse,
            reason: '$ext should be bitmap');
      }
    });

    test('returns null for unsupported extensions', () {
      expect(mediaFileFromPath('/photos/doc.pdf'), isNull);
      expect(mediaFileFromPath('/photos/video.mp4'), isNull);
      expect(mediaFileFromPath('/photos/noext'), isNull);
      // Host operating systems decode these, but not every supported platform
      // does, so they stay out of the supported set.
      expect(mediaFileFromPath('/photos/scan.tiff'), isNull);
      expect(mediaFileFromPath('/photos/next.avif'), isNull);
    });

    test('is case-insensitive', () {
      expect(mediaFileFromPath('/photos/SHOT.ARW')?.isRaw, isTrue);
      expect(mediaFileFromPath('/photos/shot.JPG')?.isRaw, isFalse);
      expect(mediaFileFromPath('/photos/shot.Cr2')?.isRaw, isTrue);
    });

    test('returns a normalised absolute path', () {
      final result = mediaFileFromPath('relative/shot.arw');
      expect(result, isNotNull);
      expect(
          result!.path,
          equals('${Directory.current.path}/relative/shot.arw'
              .replaceAll('//', '/')
              .replaceAll(RegExp(r'/+'), '/')));
    });
  });

  group('deduplicateMediaFiles', () {
    test('removes duplicates preserving first occurrence', () {
      final files = [
        MediaFile(path: '/a/shot.arw', kind: MediaKind.raw),
        MediaFile(path: '/b/other.jpg', kind: MediaKind.bitmap),
        MediaFile(path: '/a/shot.arw', kind: MediaKind.raw),
      ];
      final result = deduplicateMediaFiles(files);
      expect(result.length, 2);
      expect(result[0].path, contains('shot.arw'));
      expect(result[1].path, contains('other.jpg'));
    });

    test('returns an empty list for empty input', () {
      expect(deduplicateMediaFiles([]), isEmpty);
    });

    test('normalises paths for comparison', () {
      final files = [
        MediaFile(path: '/a//shot.arw', kind: MediaKind.raw),
        MediaFile(path: '/a/shot.arw', kind: MediaKind.raw),
      ];
      final result = deduplicateMediaFiles(files);
      expect(result.length, 1);
    });
  });

  group('listMediaFilesInDirectory', () {
    test('lists supported files by name and reports scan failures', () async {
      final root = Directory.systemTemp.createTempSync('media-library-');
      addTearDown(() => root.deleteSync(recursive: true));
      for (final name in ['b.JPG', 'a.arw', 'notes.txt']) {
        File('${root.path}/$name').writeAsStringSync('');
      }
      Directory('${root.path}/nested.arw').createSync();

      final files = await listMediaFilesInDirectory(root.path);
      expect(files.map((file) => file.path.split(Platform.pathSeparator).last),
          ['a.arw', 'b.JPG']);
      expect(files.map((file) => file.isRaw), [true, false]);

      // The scan runs on another isolate; its failure must still arrive as a
      // FileSystemException, which the gallery reports to the user.
      await expectLater(listMediaFilesInDirectory('${root.path}/missing'),
          throwsA(isA<FileSystemException>()));
    });
  });
}
