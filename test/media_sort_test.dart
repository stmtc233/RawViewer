import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/media_sort.dart';

void main() {
  test(
      'sorts ratings in both directions with stable names for ties and unrated',
      () async {
    final ratings = <String, int?>{
      'five-b': 5,
      'missing': null,
      'three': 3,
      'five-a': 5,
      'zero': 0,
      'invalid': 9,
      'failed': null,
    };
    final files = [
      for (final name in ratings.keys)
        MediaFile(path: '/$name.jpg', kind: MediaKind.bitmap)
    ];
    Future<int?> loadRating(String filePath) async {
      final name = filePath.substring(1, filePath.length - 4);
      if (name == 'failed') throw const FileSystemException('Unreadable');
      return ratings[name];
    }

    final descending = await sortMediaFiles(
        files, MediaSortOrder.ratingDescending,
        loadRating: loadRating);
    final ascending = await sortMediaFiles(
        files, MediaSortOrder.ratingAscending,
        loadRating: loadRating);
    expect(descending.map((f) => f.path), [
      '/five-a.jpg',
      '/five-b.jpg',
      '/three.jpg',
      '/failed.jpg',
      '/invalid.jpg',
      '/missing.jpg',
      '/zero.jpg',
    ]);
    expect(ascending.map((f) => f.path), [
      '/failed.jpg',
      '/invalid.jpg',
      '/missing.jpg',
      '/zero.jpg',
      '/three.jpg',
      '/five-a.jpg',
      '/five-b.jpg',
    ]);
    expect(files.first.path, '/five-b.jpg');
    await expectLater(sortMediaFiles(files, MediaSortOrder.ratingDescending),
        throwsArgumentError);
  });

  test('sorts media files by file name in both directions', () async {
    const files = [
      MediaFile(path: '/photos/IMG_010.jpg', kind: MediaKind.bitmap),
      MediaFile(path: '/photos/IMG_002.ARW', kind: MediaKind.raw),
      MediaFile(path: '/photos/IMG_001.jpg', kind: MediaKind.bitmap),
    ];

    final ascending = await sortMediaFiles(files, MediaSortOrder.nameAscending);
    final descending =
        await sortMediaFiles(files, MediaSortOrder.nameDescending);

    expect(ascending.map((file) => file.path), [
      '/photos/IMG_001.jpg',
      '/photos/IMG_002.ARW',
      '/photos/IMG_010.jpg',
    ]);
    expect(descending.map((file) => file.path), [
      '/photos/IMG_010.jpg',
      '/photos/IMG_002.ARW',
      '/photos/IMG_001.jpg',
    ]);
  });

  test('sorts media files by modification time in both directions', () async {
    final directory = await Directory.systemTemp.createTemp('rawviewer-sort-');
    addTearDown(() => directory.delete(recursive: true));
    final oldest = File('${directory.path}/oldest.jpg')..createSync();
    final newest = File('${directory.path}/newest.arw')..createSync();
    await oldest.setLastModified(DateTime(2025, 1, 1));
    await newest.setLastModified(DateTime(2025, 2, 1));
    final files = [
      MediaFile(path: newest.path, kind: MediaKind.raw),
      MediaFile(path: oldest.path, kind: MediaKind.bitmap),
    ];

    final newestFirst =
        await sortMediaFiles(files, MediaSortOrder.modifiedNewest);
    final oldestFirst =
        await sortMediaFiles(files, MediaSortOrder.modifiedOldest);

    expect(newestFirst.map((file) => file.path), [newest.path, oldest.path]);
    expect(oldestFirst.map((file) => file.path), [oldest.path, newest.path]);
  });

  test('sorts media files by capture time in both directions', () async {
    const files = [
      MediaFile(path: '/photos/newer.jpg', kind: MediaKind.bitmap),
      MediaFile(path: '/photos/older.arw', kind: MediaKind.raw),
    ];
    final capturedAt = {
      '/photos/newer.jpg': DateTime(2025, 2, 1),
      '/photos/older.arw': DateTime(2025, 1, 1),
    };

    final newestFirst = await sortMediaFiles(
      files,
      MediaSortOrder.capturedNewest,
      loadCapturedAt: (filePath) async => capturedAt[filePath]!,
    );
    final oldestFirst = await sortMediaFiles(
      files,
      MediaSortOrder.capturedOldest,
      loadCapturedAt: (filePath) async => capturedAt[filePath]!,
    );

    expect(newestFirst.map((file) => file.path), [
      '/photos/newer.jpg',
      '/photos/older.arw',
    ]);
    expect(oldestFirst.map((file) => file.path), [
      '/photos/older.arw',
      '/photos/newer.jpg',
    ]);
  });

  testWidgets('sort menu changes the selected order', (tester) async {
    var selectedSortOrder = defaultMediaSortOrder;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            appBar: AppBar(
              actions: [
                MediaSortButton(
                  selectedSortOrder: selectedSortOrder,
                  enabled: true,
                  onSelected: (sortOrder) {
                    setState(() {
                      selectedSortOrder = sortOrder;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();

    expect(find.text('Name (A-Z)'), findsOneWidget);
    expect(find.text('Capture time (newest first)'), findsOneWidget);
    expect(find.text('Rating (high to low)'), findsOneWidget);
    expect(find.text('Rating (low to high)'), findsOneWidget);

    final capturedNewest = find.ancestor(
      of: find.text('Capture time (newest first)'),
      matching: find.byType(PopupMenuItem<MediaSortOrder>),
    );
    await tester.tap(capturedNewest);
    await tester.pumpAndSettle();

    expect(selectedSortOrder, MediaSortOrder.capturedNewest);
  });
}
