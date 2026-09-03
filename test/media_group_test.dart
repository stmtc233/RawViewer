import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/media_group.dart';

void main() {
  test('adaptive groups merge matching RAW and JPEG files', () {
    final groups = buildAdaptiveMediaGroups(const [
      MediaFile(path: '/photos/IMG_0001.ARW', kind: MediaKind.raw),
      MediaFile(path: '/photos/IMG_0001.jpeg', kind: MediaKind.bitmap),
      MediaFile(path: '/photos/IMG_0001.jpg', kind: MediaKind.bitmap),
      MediaFile(path: '/photos/IMG_0002.NEF', kind: MediaKind.raw),
      MediaFile(path: '/other/IMG_0001.JPG', kind: MediaKind.bitmap),
      MediaFile(path: '/photos/preview.png', kind: MediaKind.bitmap),
    ]);

    expect(groups, hasLength(5));
    expect(groups[0].primary.path, '/photos/IMG_0001.ARW');
    expect(groups[0].pairedJpeg!.path, '/photos/IMG_0001.jpg');
    expect(groups[1].primary.path, '/photos/IMG_0001.jpeg');
    expect(groups[2].primary.path, '/photos/IMG_0002.NEF');
    expect(groups[2].hasPairedJpeg, isFalse);
    expect(groups[3].primary.path, '/other/IMG_0001.JPG');
    expect(groups[4].primary.path, '/photos/preview.png');
  });
}
