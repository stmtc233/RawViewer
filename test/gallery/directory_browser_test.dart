import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/gallery/widgets/directory_browser.dart';
import 'package:rawviewer/gallery/widgets/directory_thumbnail_tile.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/home_page.dart';
import 'package:rawviewer/core/platform_channels.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/gallery/widgets/desktop_command_bar.dart';
import 'package:rawviewer/gallery/widgets/media_thumbnail_tile.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/media_sort.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final ratio in [GridAspectRatio.ratio3x2, GridAspectRatio.adaptive]) {
    testWidgets(
        'folders share a grid row before images in every sort order with $ratio',
        (tester) async {
      await tester.runAsync(() async {
        final root = Directory.systemTemp.createTempSync('gallery-folders-');
        addTearDown(() => root.deleteSync(recursive: true));
        Directory('${root.path}/z-folder').createSync();
        File('${root.path}/a.png').writeAsBytesSync(base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='));
        SharedPreferences.setMockInitialValues({});
        const repository = PreferencesRepository();
        await repository.saveDirectoryBrowsingEnabled(true);
        await repository.saveGridAspectRatio(ratio);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
            desktopOpenChannel, (_) async => [root.path]);
        addTearDown(
            () => messenger.setMockMethodCallHandler(desktopOpenChannel, null));
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(onAppLanguageChanged: (_) {}),
        ));
        Future<void> settle() async {
          for (var i = 0; i < 10; i++) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          await tester.pumpAndSettle();
        }

        await settle();
        for (final order in MediaSortOrder.values) {
          tester
              .widget<DesktopCommandBar>(find.byType(DesktopCommandBar))
              .onMediaSortOrderSelected(order);
          await settle();
          final folder = tester.getRect(find.byType(DirectoryThumbnailTile));
          final image = tester.getRect(find.byType(MediaThumbnailTile));
          expect(folder.top, image.top);
          expect(folder.bottom, image.bottom);
          expect(folder.right, lessThan(image.left));
        }
        final mediaTile =
            tester.widget<MediaThumbnailTile>(find.byType(MediaThumbnailTile));
        final cachedTimestamp =
            mediaTile.timestampRepository.load(mediaTile.filePath);
        await tester.tap(find.text('z-folder'));
        await settle();
        expect(find.byType(MediaThumbnailTile), findsNothing);
        expect(find.byType(DirectoryThumbnailTile), findsNothing);
        await tester.tap(find.byTooltip('Up one level'));
        await settle();
        expect(find.byType(DirectoryThumbnailTile), findsOneWidget);
        expect(find.byType(MediaThumbnailTile), findsOneWidget);
        final returnedTile =
            tester.widget<MediaThumbnailTile>(find.byType(MediaThumbnailTile));
        expect(returnedTile.timestampRepository.load(returnedTile.filePath),
            same(cachedTimestamp));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }, skip: !Platform.isMacOS && !Platform.isWindows);
  }
  testWidgets('lists subfolders, navigates down and up, and refreshes',
      (tester) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('directory-browser-');
      addTearDown(() => root.deleteSync(recursive: true));
      final child = Directory('${root.path}/child')..createSync();
      File('${root.path}/photo.jpg').writeAsStringSync('');
      String currentPath = root.path;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: StatefulBuilder(builder: (context, setState) {
          return DirectoryBrowser(
            directoryPath: currentPath,
            builder: (context, directories) => GridView.count(
              crossAxisCount: 4,
              children: [
                for (final directory in directories)
                  DirectoryThumbnailTile(
                    directoryPath: directory,
                    onOpen: () => setState(() => currentPath = directory),
                  ),
              ],
            ),
            onOpenDirectory: (directory) async {
              setState(() => currentPath = directory);
            },
          );
        })),
      ));
      Future<void> finishListing() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();
      }

      await finishListing();
      expect(find.text('child'), findsOneWidget);
      expect(find.text('photo.jpg'), findsNothing);
      await tester.tap(find.text('child'));
      await tester.pump();
      await finishListing();
      expect(currentPath, child.path);
      expect(find.byType(DirectoryThumbnailTile), findsNothing);
      await tester.tap(find.byTooltip('Up one level'));
      await tester.pump();
      expect(find.text('child'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await finishListing();
      expect(currentPath, root.path);
      await Directory('${root.path}/new-folder').create();
      await tester.tap(find.byTooltip('Refresh folders'));
      await tester.pump();
      expect(find.text('child'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await finishListing();
      expect(find.text('new-folder'), findsOneWidget);
    });
  });

  testWidgets('hot folder refreshes the open directory after a file change',
      (tester) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('hot-folder-');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/first.png').writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='));
      SharedPreferences.setMockInitialValues({});
      await const PreferencesRepository().saveHotFolderEnabled(true);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          desktopOpenChannel, (_) async => [root.path]);
      addTearDown(
          () => messenger.setMockMethodCallHandler(desktopOpenChannel, null));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(onAppLanguageChanged: (_) {}),
      ));

      Future<void> waitForMediaTiles(int count) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          if (find.byType(MediaThumbnailTile).evaluate().length == count) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      // The desktop open request and directory watcher are real async I/O.
      // Wait for the initial load before creating the watched file so a slow
      // CI runner cannot create it before the watcher is subscribed.
      await waitForMediaTiles(1);
      expect(find.byType(MediaThumbnailTile), findsOneWidget);

      File('${root.path}/added.png').writeAsBytesSync(base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aD1sAAAAASUVORK5CYII='));
      await waitForMediaTiles(2);
      expect(find.byType(MediaThumbnailTile), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }, skip: !Platform.isMacOS && !Platform.isWindows && !Platform.isLinux);
}
