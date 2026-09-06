import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_repository.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:rawviewer/gallery/widgets/media_thumbnail_tile.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/rating_badge.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';

class _Exif extends ExifRepository {
  var reads = 0;
  @override
  Future<ExifMetadata> load(String path) async {
    reads++;
    return const ExifMetadata(tags: {'Image Rating': '4'});
  }
}

void main() {
  testWidgets(
      'grid rating visibility preserves the tile action and avoids hidden reads',
      (tester) async {
    final exif = _Exif();
    final ratings = RatingRepository(exifRepository: exif);
    final cache = LruCache<String, ViewerImage>(1024,
        onEvict: (_, image) => image.dispose());
    addTearDown(cache.clear);
    var taps = 0;
    Future<void> show(bool visible) async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Center(
            child: SizedBox(
          width: 100,
          height: 80,
          child: MediaThumbnailTile(
            mediaFile:
                const MediaFile(path: '/missing.jpg', kind: MediaKind.bitmap),
            hasPairedJpeg: false,
            settings: ViewerSettings(showThumbnailRatings: visible),
            timestampRepository: TimestampRepository(),
            ratingRepository: ratings,
            resizeWidth: 128,
            imageStore: ImageStore(cache),
            onTap: () => taps++,
          ),
        )),
      ));
      await tester.pumpAndSettle();
    }

    await show(false);
    expect(exif.reads, 0);
    expect(find.byType(RatingBadge), findsNothing);
    await show(true);
    expect(find.byType(RatingBadge), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(4));
    await tester.tap(find.byType(RatingBadge));
    expect(taps, 1);
    await show(false);
    expect(find.byType(RatingBadge), findsNothing);
    expect(exif.reads, 1);
    expect(tester.takeException(), isNull);
  });
}
