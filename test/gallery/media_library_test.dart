import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/gallery/media_library.dart';
import 'package:rawviewer/media_group.dart';

void main() {
  group('mediaFileFromPath', () {
    test('recognises RAW extensions as raw', () {
      for (final ext in ['.arw', '.cr2', '.cr3', '.dng', '.nef', '.orf',
                         '.raf', '.rw2', '.srw']) {
        final result = mediaFileFromPath('/photos/shot$ext');
        expect(result, isNotNull, reason: 'expected $ext to be recognised');
        expect(result!.isRaw, isTrue, reason: '$ext should be raw');
      }
    });

    test('recognises bitmap extensions as bitmap', () {
      for (final ext in ['.jpg', '.jpeg', '.png', '.webp']) {
        final result = mediaFileFromPath('/photos/shot$ext');
        expect(result, isNotNull, reason: 'expected $ext to be recognised');
        expect(result!.isRaw, isFalse, reason: '$ext should be bitmap');
      }
    });

    test('returns null for unsupported extensions', () {
      expect(mediaFileFromPath('/photos/doc.pdf'), isNull);
      expect(mediaFileFromPath('/photos/video.mp4'), isNull);
      expect(mediaFileFromPath('/photos/noext'), isNull);
    });

    test('is case-insensitive', () {
      expect(mediaFileFromPath('/photos/SHOT.ARW')?.isRaw, isTrue);
      expect(mediaFileFromPath('/photos/shot.JPG')?.isRaw, isFalse);
      expect(mediaFileFromPath('/photos/shot.Cr2')?.isRaw, isTrue);
    });

    test('returns a normalised absolute path', () {
      final result = mediaFileFromPath('relative/shot.arw');
      expect(result, isNotNull);
      expect(result!.path, equals(
          '${Directory.current.path}/relative/shot.arw'
              .replaceAll('//','/')
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
}
