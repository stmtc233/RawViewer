import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_repository.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:xml/xml.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rawviewer-exif-');
  });

  tearDown(() => directory.delete(recursive: true));

  test('adds a missing rating to existing XMP without losing its properties',
      () async {
    final file = File('${directory.path}/photo.png');
    await file.writeAsBytes(List.filled(32, 0));
    final sidecar = File('${directory.path}/photo.xmp');
    await sidecar.writeAsString(_xmpFixture()
        .replaceFirst('custom:Rating="3"', '')
        .replaceFirst('<custom:Rating>3</custom:Rating>', ''));
    final repository = ExifRepository();
    expect((await repository.load(file.path)).tags['Image Rating'], isNull);
    await repository.saveRating(file.path, 4);
    final result = await ExifRepository().load(file.path);
    expect(result.tags['Image Rating'], '4');
    expect(result.tags['XMP dc:subject'], 'Travel, Family');
    expect(result.tags['XMP other:Rating'], '9');
  });

  test('saves XMP ratings, preserves the image and invalidates paired caches',
      () async {
    final file = File('${directory.path}/photo.dng');
    final jpeg = File('${directory.path}/photo.jpg');
    final original = _tiffFixture();
    await file.writeAsBytes(original);
    await jpeg.writeAsBytes(original);
    final repository = ExifRepository();
    final ratings = RatingRepository(exifRepository: repository);
    addTearDown(repository.dispose);
    addTearDown(ratings.dispose);
    var changes = 0;
    ratings.addListener(() => changes++);
    expect(await ratings.load(file.path), 4);
    expect(await ratings.load(jpeg.path), 4);
    final unrelatedRead = ratings.load('${directory.path}/unrelated.jpg');
    await unrelatedRead;
    expect(await File('${directory.path}/photo.xmp').exists(), isFalse);

    await repository.saveRating(file.path, 2);
    expect(changes, 1);
    expect(await ratings.load(file.path), 2);
    expect(await ratings.load(jpeg.path), 2);
    expect(
        identical(
            unrelatedRead, ratings.load('${directory.path}/unrelated.jpg')),
        isTrue);
    final fresh = await ExifRepository().load(file.path);
    expect(fresh.tags['Image Rating'], '2');
    expect(fresh.numericValues['Image Rating'], 2);
    expect(fresh.tags['Image Make'], 'Fixture Camera');
    expect(await file.readAsBytes(), original);
    expect(await jpeg.readAsBytes(), original);

    await repository.saveRating(file.path, 0);
    expect((await ExifRepository().load(file.path)).tags['Image Rating'], '0');
    expect(await ratings.load(jpeg.path), 0);
    expect(await directory.list().length, 3);
  });

  test('reads XMP for formats without readable embedded metadata', () async {
    final file = File('${directory.path}/photo.cr3');
    await file.writeAsBytes(List.filled(32, 0));
    final sidecar = File('${directory.path}/photo.xmp');
    await sidecar.writeAsString(_xmpFixture());
    final metadata = await ExifRepository().load(file.path);
    expect(metadata.tags['Image Rating'], '3');
    expect(metadata.tags['XMP dc:subject'], 'Travel, Family');
    expect(metadata.xmpReadFailed, isFalse);
  });

  test('preserves other XMP properties and handles namespaces and encodings',
      () async {
    final file = File('${directory.path}/photo.dng');
    await file.writeAsBytes(_tiffFixture());
    final sidecar = File('${directory.path}/photo.XMP');
    await sidecar.writeAsString(_xmpFixture());
    await ExifRepository().saveRating(file.path, 5);
    final document = XmlDocument.parse(await sidecar.readAsString());
    final description = document
        .findAllElements('Description',
            namespaceUri: 'http://www.w3.org/1999/02/22-rdf-syntax-ns#')
        .first;
    expect(
        description.getAttribute('Rating',
            namespaceUri: 'http://ns.adobe.com/xap/1.0/'),
        '5');
    expect(
        description
            .getElement('Rating', namespaceUri: 'http://ns.adobe.com/xap/1.0/')!
            .innerText,
        '5');
    expect(
        description.getAttribute('Rating', namespaceUri: 'urn:unrelated'), '9');
    expect(
        description.getAttribute('Exposure2012',
            namespaceUri: 'http://ns.adobe.com/camera-raw-settings/1.0/'),
        '0.75');
    expect((await ExifRepository().load(file.path)).tags['XMP dc:subject'],
        'Travel, Family');
    expect(await directory.list().length, 2);
  });

  test('extension-qualified XMP takes precedence over shared sidecar',
      () async {
    final file = File('${directory.path}/photo.jpg');
    await file.writeAsBytes(_tiffFixture());
    final shared = File('${directory.path}/photo.xmp');
    await shared.writeAsString(_xmpFixture());
    final qualified = File('${file.path}.xmp');
    await qualified.writeAsString(_xmpFixture());
    await ExifRepository().saveRating(file.path, 1);
    expect((await ExifRepository().load(file.path)).tags['Image Rating'], '1');
    expect(await shared.readAsString(), _xmpFixture());
  });

  test('malformed XMP is reported and preserved when saving fails', () async {
    final file = File('${directory.path}/photo.dng');
    final original = _tiffFixture();
    await file.writeAsBytes(original);
    final sidecar = File('${directory.path}/photo.xmp');
    final repository = ExifRepository();
    for (final content in ['<broken', '<other/>']) {
      await sidecar.writeAsString(content);
      final metadata = await ExifRepository().load(file.path);
      expect(metadata.xmpReadFailed, isTrue);
      expect(metadata.tags['Image Rating'], '4');
      await expectLater(
          repository.saveRating(file.path, 1), throwsA(isA<Exception>()));
      expect(await sidecar.readAsString(), content);
      expect(await file.readAsBytes(), original);
    }
    await sidecar.writeAsString(_xmpFixture());
    await repository.saveRating(file.path, 1);
    expect((await repository.load(file.path)).tags['Image Rating'], '1');
  });

  test('serializes saves and rejects invalid ratings and missing images',
      () async {
    final file = File('${directory.path}/photo.dng');
    await file.writeAsBytes(_tiffFixture());
    final repository = ExifRepository();
    await Future.wait([
      repository.saveRating(file.path, 1),
      repository.saveRating(file.path, 5),
    ]);
    expect((await repository.load(file.path)).tags['Image Rating'], '5');
    await expectLater(repository.saveRating(file.path, 6), throwsRangeError);
    await expectLater(repository.saveRating('${directory.path}/missing.jpg', 2),
        throwsA(isA<FileSystemException>()));
    expect(await File('${directory.path}/missing.xmp').exists(), isFalse);
  });

  test('reads TIFF RAW metadata beyond the timestamp header limit', () async {
    final file = File('${directory.path}/photo.dng');
    await file.writeAsBytes(_tiffFixture());
    final metadata = await ExifRepository().load(file.path);

    expect(metadata.readFailed, isFalse);
    expect(metadata.fileSize, await file.length());
    expect(metadata.modifiedAt, isNotNull);
    expect(metadata.tags['Image Make'], 'Fixture Camera');
    expect(parseExifRating(metadata.tags['Image Rating']), 4);
    expect(metadata.tags['Image Tag 0xC001'], 'Custom metadata');
    expect(metadata.tags['EXIF ExposureTime'], '1/125');
    expect(metadata.numericValues['EXIF ExposureTime'], 1 / 125);
    expect(metadata.numericValues, isNot(contains('Image Make')));
    expect(metadata.tags['EXIF DateTimeOriginal'], '2026:09:06 12:34:56');
  });

  test('deduplicates pending and cached reads', () async {
    final file = File('${directory.path}/photo.tiff');
    await file.writeAsBytes(_tiffFixture());
    final repository = ExifRepository();
    final first = repository.load(file.path);
    expect(identical(first, repository.load(file.path)), isTrue);
    await first;
    expect(identical(first, repository.load(file.path)), isTrue);
  });

  test('missing file reports failure and does not block the next read',
      () async {
    final repository = ExifRepository();
    final missing = await repository.load('${directory.path}/missing.jpg');
    expect(missing.readFailed, isTrue);
    expect(missing.fileSize, isNull);

    final file = File('${directory.path}/plain.bmp');
    await file.writeAsBytes(List<int>.filled(32, 0));
    final plain = await repository.load(file.path);
    expect(plain.tags, isEmpty);
    expect(plain.readFailed, isFalse);
    expect(plain.fileSize, 32);
  });

  test('truncated input preserves file details without throwing', () async {
    final file = File('${directory.path}/broken.tiff');
    await file.writeAsBytes([0x49, 0x49, 0x2a, 0]);
    final metadata = await ExifRepository().load(file.path);
    expect(metadata.fileSize, 4);
    expect(metadata.tags, isEmpty);
  });
}

String _xmpFixture() => '''<?xpacket begin="" id="W5M0MpCehiHzreSzNTczkc9d"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
<r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
<r:Description r:about="" xmlns:custom="http://ns.adobe.com/xap/1.0/"
  xmlns:other="urn:unrelated" other:Rating="9" custom:Rating="3"
  xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/" crs:Exposure2012="0.75"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <custom:Rating>3</custom:Rating>
  <dc:subject><r:Bag><r:li>Travel</r:li><r:li>Family</r:li></r:Bag></dc:subject>
</r:Description></r:RDF></x:xmpmeta><?xpacket end="w"?>''';

Uint8List _tiffFixture() {
  const dataOffset = 160 * 1024;
  final bytes = Uint8List(dataOffset + 128);
  final data = ByteData.sublistView(bytes);
  void short(int offset, int value) =>
      data.setUint16(offset, value, Endian.little);
  void long(int offset, int value) =>
      data.setUint32(offset, value, Endian.little);
  void entry(int offset, int tag, int type, int count, int value) {
    short(offset, tag);
    short(offset + 2, type);
    long(offset + 4, count);
    long(offset + 8, value);
  }

  bytes.setRange(0, 4, [0x49, 0x49, 0x2a, 0]);
  long(4, 8);
  short(8, 4);
  entry(10, 0x010f, 2, 15, dataOffset);
  entry(22, 0xc001, 2, 16, dataOffset + 16);
  entry(34, 0x8769, 4, 1, 64);
  entry(46, 0x4746, 3, 1, 4);
  short(64, 2);
  entry(66, 0x829a, 5, 1, dataOffset + 32);
  entry(78, 0x9003, 2, 20, dataOffset + 40);
  bytes.setRange(dataOffset, dataOffset + 15, 'Fixture Camera\u0000'.codeUnits);
  bytes.setRange(
      dataOffset + 16, dataOffset + 32, 'Custom metadata\u0000'.codeUnits);
  long(dataOffset + 32, 1);
  long(dataOffset + 36, 125);
  bytes.setRange(
      dataOffset + 40, dataOffset + 60, '2026:09:06 12:34:56\u0000'.codeUnits);
  return bytes;
}
