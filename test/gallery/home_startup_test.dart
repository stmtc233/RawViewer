import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/app.dart';
import 'package:rawviewer/home_page.dart';
import 'package:rawviewer/gallery/widgets/desktop_command_bar.dart';
import 'package:rawviewer/gallery/widgets/media_thumbnail_tile.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/core/platform_channels.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/rating_filter_button.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump();
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Gallery did not reach the expected state');
}

Future<void> _dropPaths(WidgetTester tester, List<String> paths) {
  final done = Completer<void>();
  const codec = StandardMethodCodec();
  tester.binding.channelBuffers.push(desktopOpenChannel.name,
      codec.encodeMethodCall(MethodCall('openPaths', paths)), (reply) {
    try {
      codec.decodeEnvelope(reply!);
      done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  });
  return done.future;
}

void main() {
  testWidgets(
      'slow folder publishes files before completion and keeps partial '
      'results when the share disconnects', (tester) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('slow-gallery-');
      addTearDown(() => root.deleteSync(recursive: true));
      SharedPreferences.setMockInitialValues({});
      await const PreferencesRepository().saveShowThumbnailRatings(false);
      final scan = StreamController<List<MediaFile>>();
      addTearDown(scan.close);
      var listening = false;
      scan.onListen = () => listening = true;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          onAppLanguageChanged: (_) {},
          initialPathsLoader: () async => [root.path],
          directoryScanner: (_) => scan.stream,
        ),
      ));
      await _waitFor(tester, () => listening);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      scan.add(
          [MediaFile(path: '${root.path}/first.jpg', kind: MediaKind.bitmap)]);
      await _waitFor(
          tester, () => find.byType(MediaThumbnailTile).evaluate().isNotEmpty);
      expect(find.text('first.jpg'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // Buffered entries appear even when the server sends no further batches.
      scan.add(
          [MediaFile(path: '${root.path}/second.jpg', kind: MediaKind.bitmap)]);
      await _waitFor(
          tester, () => find.byType(MediaThumbnailTile).evaluate().length == 2);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // A failure also flushes the most recently received batch.
      scan.add(
          [MediaFile(path: '${root.path}/third.jpg', kind: MediaKind.bitmap)]);
      scan.addError(FileSystemException('SMB disconnected', root.path));
      await _waitFor(tester,
          () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
      expect(find.byType(MediaThumbnailTile), findsNWidgets(3));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('SMB disconnected'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a new drop cancels a stalled scan and opens all 4000 files',
      (tester) async {
    await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('replace-gallery-');
      addTearDown(() => root.deleteSync(recursive: true));
      final first = Directory('${root.path}/first')..createSync();
      final second = Directory('${root.path}/second')..createSync();
      SharedPreferences.setMockInitialValues({});
      await const PreferencesRepository().saveShowThumbnailRatings(false);
      var cancelled = false;
      var listening = false;
      final stalled = StreamController<List<MediaFile>>(
          onListen: () => listening = true, onCancel: () => cancelled = true);
      addTearDown(stalled.close);
      final files = [
        for (var i = 0; i < 4000; i++)
          MediaFile(path: '${second.path}/photo-$i.jpg', kind: MediaKind.bitmap)
      ];
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
          onAppLanguageChanged: (_) {},
          initialPathsLoader: () async => [first.path],
          directoryScanner: (directory) =>
              directory == first.path ? stalled.stream : Stream.value(files),
        ),
      ));
      await _waitFor(tester, () => listening);
      final drop = _dropPaths(tester, [second.path]);
      await _waitFor(
          tester,
          () =>
              find.byType(LinearProgressIndicator).evaluate().isEmpty &&
              tester
                      .widget<DesktopCommandBar>(find.byType(DesktopCommandBar))
                      .imageCount ==
                  4000);
      await drop;
      expect(cancelled, isTrue);
      final bar =
          tester.widget<DesktopCommandBar>(find.byType(DesktopCommandBar));
      expect(bar.title, second.path);
      expect(bar.imageCount, 4000);
      expect(find.byType(MediaThumbnailTile).evaluate().length, lessThan(100));
      stalled.add(
          [MediaFile(path: '${first.path}/stale.jpg', kind: MediaKind.bitmap)]);
      await tester.pump();
      expect(find.text('stale.jpg'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets(
      'an inaccessible dropped path reports an error instead of vanishing',
      (tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      final root = Directory.systemTemp.createTempSync('missing-gallery-');
      addTearDown(() => root.deleteSync(recursive: true));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomePage(
            onAppLanguageChanged: (_) {},
            initialPathsLoader: () async =>
                ['${root.path}/disconnected-share']),
      ));
      await _waitFor(tester, () => find.byType(SnackBar).evaluate().isNotEmpty);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('disconnected-share'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('gallery rating switch updates immediately and is restored',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<void> open() async {
      await tester
          .pumpWidget(MyApp(desktopWindowReady: Completer<void>().future));
      await tester.pumpAndSettle();
    }

    await open();
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .hideUnratedRatings,
        isTrue);
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .showRatings,
        isTrue);
    await tester.tap(find.byTooltip('Filter by rating'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('3 stars'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('5 stars'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .selected,
        RatingFilter.three.toggle(RatingFilter.five));
    expect(find.byType(CheckboxListTile), findsNWidgets(9));
    expect(tester.getRect(find.text('Hide unrated')).top,
        greaterThan(tester.getRect(find.text('Show ratings')).bottom));
    await tester.tap(find.text('Hide unrated'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .hideUnratedRatings,
        isFalse);
    expect(
        (await const PreferencesRepository().loadViewPreferences())
            .hideUnratedRatings,
        isFalse);
    await tester.tap(find.text('Show ratings'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .showRatings,
        isFalse);
    expect(
        (await const PreferencesRepository().loadViewPreferences())
            .showThumbnailRatings,
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await open();
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .hideUnratedRatings,
        isFalse);
    expect(
        tester
            .widget<RatingFilterButton>(find.byType(RatingFilterButton))
            .showRatings,
        isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('builds the gallery before window setup finishes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final listenerCount = windowManager.listeners.length;
    var openRequests = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(desktopOpenChannel, (_) async {
      openRequests++;
      return [];
    });
    messenger.setMockMethodCallHandler(windowsShellChannel,
        (_) async => {'supported': true, 'enabled': false});
    addTearDown(() {
      messenger.setMockMethodCallHandler(desktopOpenChannel, null);
      messenger.setMockMethodCallHandler(windowsShellChannel, null);
    });

    await tester.pumpWidget(MyApp(desktopWindowReady: ready.future));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(openRequests, 0);
    expect(windowManager.listeners.length, listenerCount);

    ready.complete();
    await tester.pumpAndSettle();
    expect(openRequests, 1);
    expect(windowManager.listeners.length, listenerCount + 1);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  testWidgets('disposing during startup does not register a window listener',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final ready = Completer<void>();
    final listenerCount = windowManager.listeners.length;
    await tester.pumpWidget(MyApp(desktopWindowReady: ready.future));
    await tester.pumpWidget(const SizedBox.shrink());

    ready.complete();
    await tester.pumpAndSettle();
    expect(windowManager.listeners.length, listenerCount);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows && !Platform.isMacOS);

  testWidgets(
      'file associations are queried when settings opens, not at launch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var associationQueries = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(desktopOpenChannel, (_) async => []);
    messenger.setMockMethodCallHandler(windowsShellChannel,
        (_) async => {'supported': true, 'enabled': false});
    messenger.setMockMethodCallHandler(fileAssociationChannel, (call) async {
      expect(call.method, 'getFileAssociationState');
      associationQueries++;
      return {'supported': true};
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(desktopOpenChannel, null);
      messenger.setMockMethodCallHandler(windowsShellChannel, null);
      messenger.setMockMethodCallHandler(fileAssociationChannel, null);
    });

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    expect(associationQueries, 0);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(associationQueries, 1);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows && !Platform.isMacOS);
}
