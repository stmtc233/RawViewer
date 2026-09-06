import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_repository.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('rawviewer-exif-');
  });

  tearDown(() => directory.delete(recursive: true));

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
