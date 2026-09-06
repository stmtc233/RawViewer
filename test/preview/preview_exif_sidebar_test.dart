import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/core/exif_sidebar_settings.dart';
import 'package:rawviewer/core/exif_repository.dart';
import 'package:rawviewer/preview/widgets/preview_exif_sidebar.dart';
import 'package:rawviewer/ui/app_theme.dart';

class _Repository extends ExifRepository {
  final requests = <String, Completer<ExifMetadata>>{};

  @override
  Future<ExifMetadata> load(String filePath) =>
      requests.putIfAbsent(filePath, Completer<ExifMetadata>.new).future;
}

Widget _app(
  _Repository repository,
  String filePath, {
  Locale? locale,
  Set<ExifSection> expandedSections = const {},
  ValueChanged<Set<ExifSection>>? onExpandedSectionsChanged,
}) {
  return MaterialApp(
    theme: rawViewerTheme,
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 336,
          child: PreviewExifSidebar(
            filePath: filePath,
            repository: repository,
            onClose: () {},
            expandedSections: expandedSections,
            onExpandedSectionsChanged: onExpandedSectionsChanged,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      'restores sections across languages without persisting search expansion',
      (tester) async {
    final repository = _Repository();
    final changes = <Set<ExifSection>>[];
    await tester.pumpWidget(_app(
      repository,
      '/metadata.jpg',
      expandedSections: {ExifSection.file},
      onExpandedSectionsChanged: changes.add,
    ));
    await tester.pump(const Duration(milliseconds: 160));
    repository.requests['/metadata.jpg']!.complete(const ExifMetadata(tags: {
      'Image Artist': 'Photographer',
    }));
    await tester.pumpAndSettle();
    expect(find.text('/metadata.jpg'), findsOneWidget);
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    expect(changes.single, isEmpty);
    await tester.enterText(find.byType(TextField), 'Image Artist');
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(ListView), matching: find.text('Image Artist')),
        findsOneWidget);
    expect(changes.length, 1);
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Image tags'));
    await tester.pumpAndSettle();
    expect(changes.last, {ExifSection.image});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(_app(
      repository,
      '/metadata.jpg',
      locale: const Locale('zh'),
      expandedSections: changes.last,
      onExpandedSectionsChanged: changes.add,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Image Artist'), findsOneWidget);
    expect(find.text('/metadata.jpg'), findsNothing);
    expect(changes.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('debounces navigation and ignores stale metadata',
      (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository, '/first.arw'));
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpWidget(_app(repository, '/skipped.arw'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(_app(repository, '/latest.jpg'));
    await tester.pump(const Duration(milliseconds: 160));
    expect(repository.requests.keys, ['/first.arw', '/latest.jpg']);

    repository.requests['/latest.jpg']!.complete(const ExifMetadata(tags: {
      'Image Model': 'Latest camera',
    }));
    await tester.pumpAndSettle();
    repository.requests['/first.arw']!.complete(const ExifMetadata(tags: {
      'Image Model': 'Old camera',
    }));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'camera');
    await tester.pumpAndSettle();
    expect(find.text('Latest camera'), findsWidgets);
    expect(find.text('Old camera'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  for (final locale in [const Locale('en'), const Locale('zh')]) {
    testWidgets('author stays visible after clearing search in $locale',
        (tester) async {
      final repository = _Repository();
      await tester.pumpWidget(_app(repository, '/author.jpg', locale: locale));
      await tester.pump(const Duration(milliseconds: 160));
      repository.requests['/author.jpg']!.complete(const ExifMetadata(tags: {
        'Image Artist': 'Example Photographer',
      }));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(PreviewExifSidebar)))!;
      final summary = find.byKey(const ValueKey('exif-shooting-summary'));
      expect(find.descendant(of: summary, matching: find.text(l10n.exifArtist)),
          findsOneWidget);
      expect(find.text('Example Photographer'), findsOneWidget);

      await tester.enterText(find.byType(TextField), l10n.exifArtist);
      await tester.pumpAndSettle();
      expect(find.text('Example Photographer'), findsWidgets);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.descendant(of: summary, matching: find.text(l10n.exifArtist)),
          findsOneWidget);
      expect(find.text('Example Photographer'), findsOneWidget);

      await tester
          .pumpWidget(_app(repository, '/no-author.jpg', locale: locale));
      await tester.pump(const Duration(milliseconds: 160));
      repository.requests['/no-author.jpg']!.complete(const ExifMetadata(tags: {
        'Image Model': 'Camera',
      }));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exifArtist), findsNothing);
      expect(find.text('Example Photographer'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows rating stars and clears them between files in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      for (final value in [
        '1',
        '2',
        '3',
        '4',
        '5',
        '0',
        null,
        '8',
        'invalid'
      ]) {
        final filePath = '/rating-$value.jpg';
        await tester.pumpWidget(_app(repository, filePath, locale: locale));
        expect(find.byKey(const ValueKey('exif-rating')), findsNothing);
        await tester.pump(const Duration(milliseconds: 160));
        repository.requests[filePath]!.complete(ExifMetadata(tags: {
          if (value != null) 'Image Rating': value,
        }));
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
            tester.element(find.byType(PreviewExifSidebar)))!;
        final expected = int.tryParse(value ?? '') ?? 0;
        final stars = expected <= 5 ? expected : 0;
        final row = find.byKey(const ValueKey('exif-rating'));
        expect(find.descendant(of: row, matching: find.byIcon(Icons.star)),
            findsNWidgets(stars));
        expect(
            find.descendant(of: row, matching: find.byIcon(Icons.star_border)),
            findsNWidgets(5 - stars));
        final status = value == null
            ? l10n.exifRatingMissing
            : value == '0'
                ? l10n.exifRatingUnrated
                : stars > 0
                    ? '$stars / 5'
                    : l10n.exifRatingInvalid;
        expect(find.text(status), findsOneWidget);
        expect(tester.getSemantics(row).label, '${l10n.exifRating}: $status');
        expect(tester.getRect(row).bottom, lessThan(180));
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(find.byType(TextField),
          locale.languageCode == 'zh' ? '星级' : 'rating');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exif-rating')), findsOneWidget);
    });

    testWidgets(
        'shows key settings together before collapsed details in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await tester
          .pumpWidget(_app(repository, '/photos/DSC01234.arw', locale: locale));
      await tester.pump(const Duration(milliseconds: 160));
      repository.requests['/photos/DSC01234.arw']!.complete(const ExifMetadata(
        tags: {
          'Image Model': 'SONY ILCE-7RM5',
          'Image Rating': '4',
          'EXIF LensModel': 'FE 24-70mm F2.8 GM II',
          'EXIF ExposureTime': '1/250',
          'EXIF FNumber': '28/5',
          'EXIF ISOSpeedRatings': '400',
          'EXIF FocalLength': '50',
          'EXIF FocalLengthIn35mmFilm': '50',
          'EXIF ExposureBiasValue': '-2/3',
          'EXIF DateTimeOriginal': '2026:09:06 12:34:56',
          'EXIF ExifImageWidth': '9504',
          'EXIF ExifImageLength': '6336',
          'EXIF ExposureProgram': 'Aperture Priority',
          'EXIF MeteringMode': 'Pattern',
          'EXIF WhiteBalance': 'Auto',
          'EXIF Flash': 'Flash did not fire',
          'EXIF ColorSpace': 'sRGB',
          'MakerNote Tag 0x1234': 'Vendor-specific value',
        },
        numericValues: {
          'EXIF FNumber': 5.6,
          'EXIF FocalLength': 50,
          'EXIF FocalLengthIn35mmFilm': 50,
          'EXIF ExposureBiasValue': -2 / 3,
        },
      ));
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(PreviewExifSidebar)))!;
      for (final value in [
        'SONY ILCE-7RM5',
        'FE 24-70mm F2.8 GM II',
        '1/250 s',
        'f/5.6',
        '400',
        '-0.67 EV',
        '2026:09:06 12:34:56',
        '9504 x 6336',
        'sRGB',
      ]) {
        final finder = find.text(value);
        expect(finder, findsOneWidget);
        expect(tester.getRect(finder).bottom, lessThan(540), reason: value);
      }
      final shutterRect = tester.getRect(find.text('1/250 s'));
      expect(
          tester.getRect(find.text('f/5.6')).center.dy, shutterRect.center.dy);
      expect(tester.getRect(find.text('400')).center.dy, shutterRect.center.dy);
      expect(find.text('EXIF ExposureTime'), findsNothing);
      expect(find.text('/photos/DSC01234.arw'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -280));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exifExifSection));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('EXIF FNumber'), 150,
          scrollable: find.descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable)));
      expect(find.text('28/5'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('searches tags and copies all metadata in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final repository = _Repository();
      final longPath = '/${List.filled(20, 'long-folder').join('/')}/photo.arw';
      await tester.pumpWidget(_app(repository, longPath, locale: locale));
      await tester.pump(const Duration(milliseconds: 160));
      repository.requests[longPath]!.complete(ExifMetadata(
        fileSize: 2048,
        modifiedAt: DateTime(2026, 9, 6),
        tags: const {
          'Image Model': 'Camera model',
          'GPS GPSLatitude': '[31, 12, 0]',
          'MakerNote Tag 0x1234': 'Vendor-specific value',
        },
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), '0x1234');
      await tester.pumpAndSettle();
      expect(find.text('MakerNote Tag 0x1234'), findsOneWidget);
      expect(find.text('Vendor-specific value'), findsOneWidget);
      expect(find.text('Camera model'), findsNothing);

      await tester.tap(find.byIcon(Icons.copy_all_outlined));
      await tester.pumpAndSettle();
      expect(clipboard, contains(longPath));
      expect(clipboard, contains('GPS GPSLatitude: [31, 12, 0]'));
      expect(clipboard, contains('Image Model: Camera model'));

      await tester.enterText(find.byType(TextField), 'no-match');
      await tester.pumpAndSettle();
      final l10n =
          AppLocalizations.of(tester.element(find.byType(PreviewExifSidebar)))!;
      expect(find.text(l10n.exifNoResults), findsOneWidget);
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exifFileSection), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows empty and failed metadata states', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(_app(repository, '/plain.png'));
    await tester.pump(const Duration(milliseconds: 160));
    repository.requests['/plain.png']!
        .complete(const ExifMetadata(fileSize: 42));
    await tester.pumpAndSettle();
    expect(find.text('No readable EXIF metadata was found in this file.'),
        findsOneWidget);
    await tester.pumpWidget(_app(repository, '/broken.jpg'));
    await tester.pump(const Duration(milliseconds: 160));
    repository.requests['/broken.jpg']!.completeError(StateError('Unreadable'));
    await tester.pumpAndSettle();
    expect(
        find.text('Could not read metadata from this file.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
