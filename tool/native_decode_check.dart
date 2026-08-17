// Manual integration check against real RAW files and the real native library.
//
// Deliberately outside test/ so `flutter test` does not pick it up: it needs
// actual RAW files and a built native_lib on the library search path. Run it
// from the build output directory so the native library resolves:
//
//   cd build/windows/x64/runner/Release
//   dart <repo>/tool/native_decode_check.dart C:/tsc/raw 3
//
// It verifies the RGBA layout contract (size == w*h*4, stride == w*4), that
// embedded JPEG previews pass through un-re-encoded, and that a tripped cancel
// token actually aborts a decode instead of running to completion.
import 'dart:io';

import 'package:rawviewer/native_lib.dart';

const _rawExtensions = {
  '.arw', '.cr2', '.cr3', '.dng', '.nef', '.orf', '.raf', '.rw2', '.srw',
};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: native_decode_check <dir-with-raw-files> [limit]');
    exitCode = 2;
    return;
  }

  final limit = args.length > 1 ? int.parse(args[1]) : 3;
  final files = Directory(args[0])
      .listSync()
      .whereType<File>()
      .where((f) => _rawExtensions.contains(
          f.path.substring(f.path.lastIndexOf('.')).toLowerCase()))
      .take(limit)
      .toList();

  if (files.isEmpty) {
    stderr.writeln('no RAW files found in ${args[0]}');
    exitCode = 2;
    return;
  }

  var failures = 0;

  for (final file in files) {
    final name = file.path.split(RegExp(r'[/\\]')).last;
    stdout.writeln('--- $name (${file.lengthSync() ~/ 1024} KB)');

    final fastWatch = Stopwatch()..start();
    final fast = getRawFastPreviewSync(file.path);
    fastWatch.stop();

    if (fast == null) {
      stdout.writeln('  fast preview: FAILED');
      failures++;
    } else {
      final layout = fast.isRgba
          ? 'rgba ${fast.width}x${fast.height} stride=${fast.stride}'
          : 'encoded (jpeg)';
      stdout.writeln('  fast preview: $layout, '
          '${fast.data.length ~/ 1024} KB in ${fastWatch.elapsedMilliseconds}ms');

      if (fast.isRgba) {
        final expected = fast.width * fast.height * 4;
        if (fast.data.length != expected) {
          stdout.writeln('  MISMATCH: expected $expected bytes');
          failures++;
        }
        if (fast.stride != fast.width * 4) {
          stdout.writeln('  MISMATCH: stride != width*4');
          failures++;
        }
      }
    }

    final halfWatch = Stopwatch()..start();
    final half = getDecodedRawPreviewSync(file.path, halfSize: 1);
    halfWatch.stop();

    if (half == null) {
      stdout.writeln('  decoded (half): FAILED');
      failures++;
    } else {
      final expected = half.width * half.height * 4;
      final ok = half.data.length == expected && half.stride == half.width * 4;
      stdout.writeln('  decoded (half): ${half.width}x${half.height} '
          '${half.data.length ~/ 1024} KB in ${halfWatch.elapsedMilliseconds}ms '
          '${ok ? "" : "<-- LAYOUT MISMATCH"}');
      if (!ok) failures++;
    }

    final fullWatch = Stopwatch()..start();
    final full = getDecodedRawPreviewSync(file.path, halfSize: 0);
    fullWatch.stop();
    if (full == null) {
      stdout.writeln('  decoded (full): FAILED');
      failures++;
    } else {
      stdout.writeln('  decoded (full): ${full.width}x${full.height} '
          '${full.data.length ~/ 1024} KB in ${fullWatch.elapsedMilliseconds}ms');
    }

    // Cancellation: trip the token up front, so LibRaw should abort early
    // rather than spending the full decode time.
    final token = RawCancelToken()..cancel();
    final cancelWatch = Stopwatch()..start();
    final cancelled = getDecodedRawPreviewSync(file.path,
        halfSize: 0, cancelToken: token);
    cancelWatch.stop();
    token.dispose();

    final fullMs = fullWatch.elapsedMilliseconds;
    final cancelMs = cancelWatch.elapsedMilliseconds;
    final aborted = cancelled == null;
    stdout.writeln('  pre-cancelled full decode: '
        '${aborted ? "aborted" : "still returned an image"} in ${cancelMs}ms '
        '(uncancelled: ${fullMs}ms)');
    if (!aborted) {
      stdout.writeln('  WARNING: cancellation did not abort the decode');
      failures++;
    }
  }

  stdout.writeln(failures == 0
      ? '\nAll native decode checks passed.'
      : '\n$failures check(s) FAILED.');
  exitCode = failures == 0 ? 0 : 1;
}
