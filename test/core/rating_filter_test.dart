import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_repository.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:rawviewer/media_group.dart';

class _Exif extends ExifRepository {
  final Future<ExifMetadata> Function(String) read;
  _Exif(this.read);
  @override
  Future<ExifMetadata> load(String filePath) => read(filePath);

  void changed() => notifyListeners();
}

MediaGroup _group(String path) =>
    MediaGroup(primary: MediaFile(path: path, kind: MediaKind.bitmap));

Future<void> _finish(RatingFilterController controller) async {
  if (!controller.loading) return;
  final done = Completer<void>();
  void listen() {
    if (!controller.loading) done.complete();
  }

  controller.addListener(listen);
  await done.future;
  controller.removeListener(listen);
}

void main() {
  test('metadata changes refresh active filters and detach on disposal',
      () async {
    var rating = '3';
    final exif =
        _Exif((_) async => ExifMetadata(tags: {'Image Rating': rating}));
    final ratings = RatingRepository(exifRepository: exif);
    final gallery = RatingFilterController(ratings);
    final preview = RatingFilterController(ratings);
    final all = RatingFilterController(ratings);
    final groups = [_group('photo')];
    gallery.update(groups: groups, filter: RatingFilter.three);
    preview.update(groups: groups, filter: RatingFilter.five);
    all.update(groups: groups);
    await _finish(gallery);
    await _finish(preview);
    expect(gallery.visibleGroups, groups);
    expect(preview.visibleGroups, isEmpty);
    rating = '5';
    exif.changed();
    await _finish(gallery);
    await _finish(preview);
    expect(gallery.visibleGroups, isEmpty);
    expect(preview.visibleGroups, groups);
    expect(all.visibleGroups, groups);
    gallery.dispose();
    preview.dispose();
    all.dispose();
    exif.changed();
    ratings.dispose();
    exif.changed();
    exif.dispose();
  });

  test('exact ratings distinguish zero, absent and invalid metadata', () {
    expect(parseExifRating(' 5 '), 5);
    for (final value in [null, '', '-1', '6', '2.5', 'unknown']) {
      expect(parseExifRating(value), isNull);
    }
    expect(parseExifRating('0'), 0);
    expect(RatingFilter.three.includes(3), isTrue);
    expect(RatingFilter.three.includes(4), isFalse);
    expect(RatingFilter.unrated.includes(null), isTrue);
    expect(RatingFilter.unrated.includes(0), isTrue);
    expect(RatingFilter.all.includes(null), isTrue);
  });

  test('rating reads deduplicate and survive metadata read failures', () async {
    var reads = 0;
    final metadata = Completer<ExifMetadata>();
    final repository = RatingRepository(exifRepository: _Exif((_) {
      reads++;
      return metadata.future;
    }));
    final first = repository.load('a');
    expect(identical(first, repository.load('a')), isTrue);
    metadata.completeError(StateError('unreadable'));
    expect(await first, isNull);
    expect(await repository.load('a'), isNull);
    expect(reads, 1);
  });

  test('multi-selection toggles ratings independently and resets to all', () {
    final selected =
        RatingFilter.all.toggle(RatingFilter.three).toggle(RatingFilter.five);
    expect(selected.includes(3), isTrue);
    expect(selected.includes(5), isTrue);
    expect(selected.includes(4), isFalse);
    expect(selected.includes(null), isFalse);
    expect(selected.isSelected(RatingFilter.three), isTrue);
    expect(selected.isSelected(RatingFilter.all), isFalse);
    expect(selected.toggle(RatingFilter.three), RatingFilter.five);
    expect(selected.toggle(RatingFilter.all), RatingFilter.all);
    expect(RatingFilter.five.toggle(RatingFilter.five), RatingFilter.all);
    expect(selected.toggle(RatingFilter.unrated).includes(null), isTrue);
  });

  test('filters primary-file ratings in order and restores the full set',
      () async {
    final ratings = {'raw': '3', 'paired': '5', 'three': '3', 'five': '5'};
    final controller = RatingFilterController(RatingRepository(
      exifRepository: _Exif((path) async => ExifMetadata(tags: {
            if (ratings[path] != null) 'Image Rating': ratings[path]!,
          })),
    ));
    addTearDown(controller.dispose);
    final groups = [
      const MediaGroup(
        primary: MediaFile(path: 'raw', kind: MediaKind.raw),
        pairedJpeg: MediaFile(path: 'paired', kind: MediaKind.bitmap),
      ),
      _group('five'),
      _group('three'),
      _group('missing'),
    ];
    controller.update(groups: groups, filter: RatingFilter.three);
    await _finish(controller);
    expect(
        controller.visibleGroups.map((g) => g.primary.path), ['raw', 'three']);
    controller.update(filter: RatingFilter.three.toggle(RatingFilter.five));
    await _finish(controller);
    expect(controller.visibleGroups.map((g) => g.primary.path),
        ['raw', 'five', 'three']);
    controller.update(filter: RatingFilter.unrated);
    await _finish(controller);
    expect(controller.visibleGroups.single.primary.path, 'missing');
    controller.update(filter: RatingFilter.all);
    expect(controller.visibleGroups, groups);
  });

  test('changing folders or clearing a filter ignores in-flight results',
      () async {
    final pending = Completer<ExifMetadata>();
    final reads = <String>[];
    final controller = RatingFilterController(RatingRepository(
      exifRepository: _Exif((path) {
        reads.add(path);
        return path == 'old'
            ? pending.future
            : Future.value(const ExifMetadata(tags: {'Image Rating': '5'}));
      }),
    ));
    addTearDown(controller.dispose);
    controller.update(
        groups: [_group('old'), _group('unused')], filter: RatingFilter.three);
    controller.update(groups: [_group('new')], filter: RatingFilter.five);
    await _finish(controller);
    pending.complete(const ExifMetadata(tags: {'Image Rating': '3'}));
    await Future<void>.delayed(Duration.zero);
    expect(controller.visibleGroups.single.primary.path, 'new');
    expect(reads, isNot(contains('unused')));
    controller.update(filter: RatingFilter.one);
    controller.update(filter: RatingFilter.all);
    await Future<void>.delayed(Duration.zero);
    expect(controller.visibleGroups.single.primary.path, 'new');
  });

  test('disposal stops scanning after the active read', () async {
    final pending = Completer<ExifMetadata>();
    var reads = 0;
    final controller = RatingFilterController(RatingRepository(
      exifRepository: _Exif((_) {
        reads++;
        return pending.future;
      }),
    ));
    controller
        .update(groups: [_group('a'), _group('b')], filter: RatingFilter.one);
    controller.dispose();
    pending.complete(const ExifMetadata());
    await Future<void>.delayed(Duration.zero);
    expect(reads, 1);
  });
}
