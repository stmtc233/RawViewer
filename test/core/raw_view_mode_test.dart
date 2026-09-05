import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/raw_view_mode.dart';

void main() {
  group('resolveRawViewMode', () {
    test('keeps the preferred mode when this file can show it', () {
      for (final mode in RawViewMode.values) {
        expect(
          resolveRawViewMode(
            preferred: mode,
            hasEmbeddedJpeg: true,
            hasPairedJpeg: true,
          ),
          mode,
        );
      }
    });

    test('falls back to decoded RAW when there is no embedded JPEG', () {
      expect(
        resolveRawViewMode(
          preferred: RawViewMode.embeddedJpeg,
          hasEmbeddedJpeg: false,
          hasPairedJpeg: true,
        ),
        RawViewMode.decodedRaw,
      );
    });

    test('falls back to decoded RAW when there is no paired JPEG', () {
      expect(
        resolveRawViewMode(
          preferred: RawViewMode.pairedJpeg,
          hasEmbeddedJpeg: true,
          hasPairedJpeg: false,
        ),
        RawViewMode.decodedRaw,
      );
    });

    test('decoded RAW is always reachable, even with no other source', () {
      // Every RAW file can be decoded, so this mode never needs a fallback and
      // is what the other two fall back to.
      expect(
        resolveRawViewMode(
          preferred: RawViewMode.decodedRaw,
          hasEmbeddedJpeg: false,
          hasPairedJpeg: false,
        ),
        RawViewMode.decodedRaw,
      );
    });

    test('resolves to an available mode for every combination', () {
      for (final preferred in RawViewMode.values) {
        for (final hasEmbeddedJpeg in [true, false]) {
          for (final hasPairedJpeg in [true, false]) {
            final resolved = resolveRawViewMode(
              preferred: preferred,
              hasEmbeddedJpeg: hasEmbeddedJpeg,
              hasPairedJpeg: hasPairedJpeg,
            );
            expect(
              isRawViewModeAvailable(
                resolved,
                hasEmbeddedJpeg: hasEmbeddedJpeg,
                hasPairedJpeg: hasPairedJpeg,
              ),
              isTrue,
              reason: 'preferred=$preferred embedded=$hasEmbeddedJpeg '
                  'paired=$hasPairedJpeg resolved to unavailable $resolved',
            );
          }
        }
      }
    });
  });

  group('isRawViewModeAvailable', () {
    test('gates each mode on its own source', () {
      expect(
        isRawViewModeAvailable(RawViewMode.embeddedJpeg,
            hasEmbeddedJpeg: false, hasPairedJpeg: true),
        isFalse,
      );
      expect(
        isRawViewModeAvailable(RawViewMode.pairedJpeg,
            hasEmbeddedJpeg: true, hasPairedJpeg: false),
        isFalse,
      );
      expect(
        isRawViewModeAvailable(RawViewMode.decodedRaw,
            hasEmbeddedJpeg: false, hasPairedJpeg: false),
        isTrue,
      );
    });
  });
}
