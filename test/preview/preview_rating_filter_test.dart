import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_repository.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/media_sort.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/preview/widgets/preview_filmstrip.dart';
import 'package:rawviewer/rating_badge.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';

class _Exif extends ExifRepository {
  final overrides = <String, String>{};

  void changeRating(String path, String rating) {
    overrides[path] = rating;
    notifyListeners();
  }

  @override
  Future<ExifMetadata> load(String path) async => ExifMetadata(tags: {
        'Image Rating': overrides[path] ?? (path.contains('five') ? '5' : '3'),
      });
}

void main() {
  testWidgets(
      'a newer sort wins while ratings are loading and disposal is safe',
      (tester) async {
    final pending = Completer<int?>();
    final ratings = _PendingRatingRepository(pending);
    final cache = LruCache<String, ViewerImage>(1024,
        onEvict: (_, image) => image.dispose());
    addTearDown(cache.clear);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImagePreviewPage(
        mediaGroups: [
          for (final name in ['a', 'b', 'c'])
            MediaGroup(
                primary: MediaFile(path: '/$name.jpg', kind: MediaKind.bitmap)),
        ],
        initialIndex: 1,
        ratingRepository: ratings,
        thumbnailResizeWidth: 256,
        imageStore: ImageStore(cache),
        timestampRepository: TimestampRepository(),
        initialSettings: const ViewerSettings(showThumbnailRatings: false),
        onClose: () {},
        onRawViewModeChanged: (_) {},
        onPreviewFilmstripHeightChanged: (_) {},
      ),
    ));
    await tester.pumpAndSettle();
    Future<void> sort(String label) async {
      await tester.tap(find.byType(MediaSortButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await sort('Rating (high to low)');
    await sort('Name (Z-A)');
    PreviewFilmstrip strip() => tester.widget(find.byType(PreviewFilmstrip));
    expect(strip().mediaGroups.map((g) => g.primary.path),
        ['/c.jpg', '/b.jpg', '/a.jpg']);
    strip().onIndexSelected(0);
    await tester.pumpAndSettle();
    pending.complete(3);
    await tester.pumpAndSettle();
    expect(strip().mediaGroups.map((g) => g.primary.path),
        ['/c.jpg', '/b.jpg', '/a.jpg']);
    expect(find.text('c.jpg'), findsOneWidget);
    final nextPending = Completer<int?>();
    ratings.next = nextPending.future;
    await sort('Rating (low to high)');
    await tester.pumpWidget(const SizedBox.shrink());
    nextPending.complete(2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    ratings.dispose();
  });

  for (final width in [360.0, 1000.0]) {
    testWidgets(
        'filters navigation, recovers from empty results, toggles all ratings at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = LruCache<String, ViewerImage>(1024,
          onEvict: (_, image) => image.dispose());
      addTearDown(cache.clear);
      final filters = <RatingFilter>[];
      final sorts = <MediaSortOrder>[];
      final exif = _Exif();
      final visibility = <bool>[];
      final hideUnrated = <bool>[];
      final filmstripVisibility = <bool>[];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImagePreviewPage(
          mediaGroups: [
            for (final name in ['three', 'five', 'three-b'])
              MediaGroup(
                  primary:
                      MediaFile(path: '/$name.jpg', kind: MediaKind.bitmap))
          ],
          initialIndex: 2,
          initialRatingFilter: RatingFilter.three,
          ratingRepository: RatingRepository(exifRepository: exif),
          initialSortOrder: MediaSortOrder.capturedNewest,
          onSortOrderChanged: sorts.add,
          onRatingFilterChanged: filters.add,
          onThumbnailRatingsVisibilityChanged: visibility.add,
          onHideUnratedRatingsChanged: hideUnrated.add,
          onPreviewFilmstripVisibilityChanged: filmstripVisibility.add,
          thumbnailResizeWidth: 256,
          imageStore: ImageStore(cache),
          timestampRepository: TimestampRepository(),
          initialSettings: const ViewerSettings(hideUnratedRatings: true),
          onClose: () {},
          onRawViewModeChanged: (_) {},
          onPreviewFilmstripHeightChanged: (_) {},
        ),
      ));
      await tester.pumpAndSettle();
      PreviewFilmstrip strip() => tester.widget(find.byType(PreviewFilmstrip));
      expect(strip().hideUnratedRatings, isTrue);
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/three.jpg', '/three-b.jpg']);
      expect(strip().currentIndex, 1);
      expect(find.text('three-b.jpg'), findsOneWidget);

      final panel = tester.getRect(find.byType(PreviewFilmstrip));
      final filterButton = tester.getRect(find.byTooltip('Filter by rating'));
      final sortButton = tester.getRect(find.byType(MediaSortButton));
      final closeButton =
          tester.getRect(find.byKey(const ValueKey('preview-filmstrip-close')));
      expect(filterButton.left, greaterThan(panel.center.dx));
      expect(closeButton.left, greaterThanOrEqualTo(filterButton.right));
      expect(sortButton.left, greaterThanOrEqualTo(filterButton.right));
      expect(sortButton.right, lessThanOrEqualTo(closeButton.left));
      expect(panel.contains(sortButton.bottomRight), isTrue);
      expect(
          tester
              .widget<MediaSortButton>(find.byType(MediaSortButton))
              .selectedSortOrder,
          MediaSortOrder.capturedNewest);
      expect(closeButton.center.dy, lessThan(panel.center.dy));
      expect(panel.contains(closeButton.bottomRight), isTrue);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('preview-filmstrip-controls'))),
        filterButton.expandToInclude(closeButton),
      );

      await tester.tap(find.byTooltip('Filter by rating'));
      await tester.pumpAndSettle();

      Future<void> choose(String label) async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(CheckboxListTile), findsNWidgets(9));
        expect(tester.takeException(), isNull);
      }

      await choose('5 stars');
      expect(strip().mediaGroups, hasLength(3));
      expect(strip().currentIndex, 2);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, '3 stars'))
              .value,
          isTrue);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.widgetWithText(CheckboxListTile, '5 stars'))
              .value,
          isTrue);
      await choose('3 stars');
      expect(strip().mediaGroups.single.primary.path, '/five.jpg');
      expect(strip().currentIndex, 0);
      expect(find.text('five.jpg'), findsOneWidget);
      await choose('1 star');
      expect(strip().mediaGroups.single.primary.path, '/five.jpg');
      await choose('5 stars');
      expect(find.byType(PageView), findsNothing);
      expect(find.byTooltip('Filter by rating'), findsOneWidget);
      await choose('All ratings');
      expect(strip().mediaGroups, hasLength(3));
      expect(strip().currentIndex, 1);
      expect(find.text('five.jpg'), findsOneWidget);

      await choose('Hide unrated');
      expect(strip().hideUnratedRatings, isFalse);
      expect(
          tester
              .widgetList<RatingBadge>(find.byType(RatingBadge))
              .every((badge) => !badge.hideUnratedRatings),
          isTrue);
      await choose('Hide unrated');
      expect(strip().hideUnratedRatings, isTrue);
      expect(
          tester
              .widgetList<RatingBadge>(find.byType(RatingBadge))
              .every((badge) => badge.hideUnratedRatings),
          isTrue);
      expect(hideUnrated, [false, true]);
      expect(strip().mediaGroups, hasLength(3));
      await choose('Show ratings');
      expect(strip().showRatings, isFalse);
      expect(find.byType(RatingBadge), findsNothing);
      expect(visibility, [false]);
      await choose('Show ratings');
      expect(strip().showRatings, isTrue);
      expect(find.byType(RatingBadge), findsWidgets);
      expect(visibility, [false, true]);
      expect(filters, [
        RatingFilter.three.toggle(RatingFilter.five),
        RatingFilter.five,
        RatingFilter.five.toggle(RatingFilter.one),
        RatingFilter.one,
        RatingFilter.all,
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      strip().onIndexSelected(2);
      await tester.pumpAndSettle();
      expect(find.text('three-b.jpg'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preview-filmstrip-close')));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFilmstrip), findsNothing);
      expect(find.text('three-b.jpg'), findsOneWidget);
      expect(filmstripVisibility, [false]);
      await tester.tap(find.byTooltip('Preview display'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thumbnail navigation'));
      await tester.pumpAndSettle();
      expect(find.byType(PreviewFilmstrip), findsOneWidget);
      expect(filmstripVisibility, [false, true]);
      Future<void> sort(String label) async {
        await tester.tap(find.byType(MediaSortButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await sort('Rating (high to low)');
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/five.jpg', '/three-b.jpg', '/three.jpg']);
      expect(find.text('three-b.jpg'), findsOneWidget);
      expect(strip().currentIndex, 1);
      await sort('Rating (low to high)');
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/three-b.jpg', '/three.jpg', '/five.jpg']);
      expect(strip().currentIndex, 0);
      exif.changeRating('/three-b.jpg', '5');
      await tester.pumpAndSettle();
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/three.jpg', '/five.jpg', '/three-b.jpg']);
      expect(find.text('three-b.jpg'), findsOneWidget);
      expect(strip().currentIndex, 2);
      await tester.tap(find.byTooltip('Filter by rating'));
      await tester.pumpAndSettle();
      await choose('5 stars');
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/five.jpg', '/three-b.jpg']);
      await choose('All ratings');
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/three.jpg', '/five.jpg', '/three-b.jpg']);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await sort('Name (Z-A)');
      expect(strip().mediaGroups.map((g) => g.primary.path),
          ['/three.jpg', '/three-b.jpg', '/five.jpg']);
      expect(find.text('three-b.jpg'), findsOneWidget);
      expect(sorts, [
        MediaSortOrder.ratingDescending,
        MediaSortOrder.ratingAscending,
        MediaSortOrder.nameDescending
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('a reused rating badge never shows the previous file rating',
      (tester) async {
    final pending = Completer<int?>();
    final repository = _PendingRatingRepository(pending);
    Future<void> show(String path) => tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Center(
              child: RatingBadge(filePath: path, repository: repository)),
        ));
    await show('old');
    await tester.pump();
    expect(find.byIcon(Icons.star), findsNWidgets(5));
    await show('new');
    expect(find.byIcon(Icons.star), findsNothing);
    pending.complete(2);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.star), findsNWidgets(2));
  });
}

class _PendingRatingRepository extends RatingRepository {
  final Completer<int?> pending;
  Future<int?>? next;
  _PendingRatingRepository(this.pending);
  @override
  Future<int?> load(String path) =>
      path == 'old' ? Future.value(5) : next ?? pending.future;
}
