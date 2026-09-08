import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/live_photo.dart';

String _xmp(String attributes, [String content = '']) => '''
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
   xmlns:Container="http://ns.google.com/photos/1.0/container/"
   xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
   $attributes>$content</rdf:Description>
 </rdf:RDF>
</x:xmpmeta>''';

final _movie = <int>[0, 0, 0, 16, ...ascii.encode('ftypmp42'), 0, 0, 0, 0];

List<int> _motionJpeg(String xmp, List<int> movie) {
  final app1 = [
    ...ascii.encode('http://ns.adobe.com/xap/1.0/\u0000'),
    ...utf8.encode(xmp)
  ];
  final size = app1.length + 2;
  return [
    0xff,
    0xd8,
    0xff,
    0xe1,
    size >> 8,
    size & 0xff,
    ...app1,
    0xff,
    0xd9,
    ...movie
  ];
}

void main() {
  test('v1 requires motion flag and validates offset bounds', () {
    expect(
        motionPhotoRangeFromXmp(
            _xmp('GCamera:MicroVideo="1" GCamera:MicroVideoOffset="30"'), 100),
        (offset: 70, length: 30));
    for (final offset in ['-1', '0', '15', '100', '101', 'broken']) {
      expect(
          motionPhotoRangeFromXmp(
              _xmp('GCamera:MicroVideo="1" GCamera:MicroVideoOffset="$offset"'),
              100),
          isNull);
    }
    expect(motionPhotoRangeFromXmp(_xmp('GCamera:MicroVideoOffset="30"'), 100),
        isNull);
    expect(motionPhotoRangeFromXmp('<broken', 100), isNull);
  });

  test('v2 locates movie before later resources and honors padding', () {
    final xmp = _xmp('GCamera:MotionPhoto="1"', '''
    <Container:Directory><rdf:Seq>
      <rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="image/jpeg"
        Item:Semantic="Primary" Item:Length="0" Item:Padding="4"/></rdf:li>
      <rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="video/mp4"
        Item:Semantic="MotionPhoto" Item:Length="30" Item:Padding="2"/></rdf:li>
      <rdf:li rdf:parseType="Resource"><Container:Item Item:Mime="application/octet-stream"
        Item:Semantic="Depth" Item:Length="10"/></rdf:li>
    </rdf:Seq></Container:Directory>''');
    expect(motionPhotoRangeFromXmp(xmp, 100), (offset: 58, length: 30));
    expect(motionPhotoRangeFromXmp(xmp, 20), isNull);
    expect(
        motionPhotoRangeFromXmp(
            xmp.replaceAll('Item:Padding="2"', 'Item:Padding="-2"'), 100),
        isNull);
  });

  test('XMP uses namespace URIs, including element-form camera properties', () {
    final xmp = _xmp(
            '',
            '<GCamera:MicroVideo>1</GCamera:MicroVideo>'
                '<GCamera:MicroVideoOffset>30</GCamera:MicroVideoOffset>')
        .replaceAll('GCamera:', 'Camera:')
        .replaceAll('xmlns:GCamera=', 'xmlns:Camera=');
    expect(motionPhotoRangeFromXmp(xmp, 100), (offset: 70, length: 30));
    expect(
        motionPhotoRangeFromXmp(
            xmp.replaceAll(
                'http://ns.google.com/photos/1.0/camera/', 'unrelated'),
            100),
        isNull);
  });

  group('filesystem discovery and playback ownership', () {
    late Directory directory;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('live-test-');
    });
    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test('pairs case-insensitive MOV siblings but never unrelated movies',
        () async {
      final photo =
          await File('${directory.path}/IMG_1.HEIC').writeAsBytes([1]);
      final unrelated =
          await File('${directory.path}/other.mov').writeAsBytes(_movie);
      expect(await findLivePhoto(photo.path), isNull);
      final movie =
          await File('${directory.path}/img_1.MOV').writeAsBytes(_movie);
      final source = await findLivePhoto(photo.path);
      expect(source!.path, movie.path);
      expect(source.isEmbedded, isFalse);
      final playback = await LivePhotoPlaybackFile.prepare(source);
      await playback.dispose();
      expect(await movie.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    });

    test(
        'extracts only the declared video range and deletes its temporary copy',
        () async {
      final photo = await File('${directory.path}/motion.jpg').writeAsBytes(
          _motionJpeg(
              _xmp('GCamera:MicroVideo="1" GCamera:MicroVideoOffset="16"'),
              _movie));
      final source = await findLivePhoto(photo.path);
      expect(source, isNotNull);
      expect(source!.isEmbedded, isTrue);
      final playback = await LivePhotoPlaybackFile.prepare(source);
      expect(await File(playback.path).readAsBytes(), _movie);
      await playback.dispose();
      await playback.dispose();
      expect(await File(playback.path).exists(), isFalse);
      expect(await photo.exists(), isTrue);
    });

    test('rejects fake video payloads, truncated segments and missing files',
        () async {
      final photo = File('${directory.path}/motion.jpg');
      expect(await findLivePhoto(photo.path), isNull);
      await photo.writeAsBytes(_motionJpeg(
          _xmp('GCamera:MicroVideo="1" GCamera:MicroVideoOffset="16"'),
          List.filled(16, 0)));
      expect(await findLivePhoto(photo.path), isNull);
      await photo.writeAsBytes([0xff, 0xd8, 0xff, 0xe1, 0xff, 0xff]);
      expect(await findLivePhoto(photo.path), isNull);
      await expectLater(
          LivePhotoPlaybackFile.prepare(
              LivePhotoSource(photo.path, offset: 6, length: 16)),
          throwsA(isA<FileSystemException>()));
    });
  });
}
