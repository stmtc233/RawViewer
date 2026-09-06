import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media_group.dart';
import 'exif_repository.dart';
import 'xmp_sidecar.dart';

@immutable
class RatingFilter {
  final int _mask;
  const RatingFilter._(this._mask);

  static const all = RatingFilter._(63);
  static const unrated = RatingFilter._(1);
  static const one = RatingFilter._(2);
  static const two = RatingFilter._(4);
  static const three = RatingFilter._(8);
  static const four = RatingFilter._(16);
  static const five = RatingFilter._(32);
  static const values = [all, unrated, one, two, three, four, five];

  bool includes(int? rating) => _mask & (1 << (rating ?? 0)) != 0;

  bool isSelected(RatingFilter option) =>
      option == all ? this == all : this != all && _mask & option._mask != 0;

  RatingFilter toggle(RatingFilter option) {
    if (option == all) return all;
    if (this == all) return option;
    final mask = _mask ^ option._mask;
    return mask == 0 ? all : RatingFilter._(mask);
  }

  @override
  bool operator ==(Object other) =>
      other is RatingFilter && _mask == other._mask;

  @override
  int get hashCode => _mask.hashCode;
}

class RatingRepository extends ChangeNotifier {
  final ExifRepository exifRepository;
  final bool _ownsExifRepository;
  final _cache = <String, Future<int?>>{};

  RatingRepository({ExifRepository? exifRepository})
      : _ownsExifRepository = exifRepository == null,
        exifRepository = exifRepository ?? ExifRepository() {
    this.exifRepository.addListener(_onMetadataChanged);
  }

  void _onMetadataChanged() {
    final savedPath = exifRepository.lastRatingSavedPath;
    _cache.removeWhere(
        (path, _) => savedPath == null || sharesXmpSidecar(path, savedPath));
    notifyListeners();
  }

  @override
  void dispose() {
    exifRepository.removeListener(_onMetadataChanged);
    if (_ownsExifRepository) exifRepository.dispose();
    super.dispose();
  }

  Future<int?> load(String path) {
    final cached = _cache.remove(path);
    final result = cached ?? _read(path);
    _cache[path] = result;
    while (_cache.length > 8192) {
      _cache.remove(_cache.keys.first);
    }
    return result;
  }

  Future<int?> _read(String path) async {
    try {
      return parseExifRating(
          (await exifRepository.load(path)).tags['Image Rating']);
    } catch (_) {
      return null;
    }
  }
}

/// Publishes a complete result so metadata arrival cannot reorder navigation.
class RatingFilterController extends ChangeNotifier {
  final RatingRepository repository;
  List<MediaGroup> _groups = const [];
  List<MediaGroup> get groups => _groups;
  List<MediaGroup> visibleGroups = const [];
  RatingFilter selected = RatingFilter.all;
  bool loading = false;
  int _generation = 0;

  RatingFilterController(this.repository) {
    repository.addListener(_onRatingsChanged);
  }

  void _onRatingsChanged() {
    if (selected != RatingFilter.all) update();
  }

  void update({List<MediaGroup>? groups, RatingFilter? filter}) {
    if (groups != null) _groups = List.unmodifiable(groups);
    if (filter != null) selected = filter;
    final generation = ++_generation;
    if (selected == RatingFilter.all) {
      loading = false;
      visibleGroups = _groups;
      notifyListeners();
      return;
    }
    loading = true;
    // Old results may belong to a different folder or filter.
    visibleGroups = const [];
    notifyListeners();
    unawaited(_filter(generation, _groups, selected));
  }

  Future<void> _filter(
      int generation, List<MediaGroup> groups, RatingFilter filter) async {
    final matches = <MediaGroup>[];
    for (final group in groups) {
      if (generation != _generation) return;
      final rating = await repository.load(group.primary.path);
      if (generation != _generation) return;
      if (filter.includes(rating)) matches.add(group);
    }
    if (generation != _generation) return;
    visibleGroups = List.unmodifiable(matches);
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    repository.removeListener(_onRatingsChanged);
    _generation++;
    super.dispose();
  }
}
