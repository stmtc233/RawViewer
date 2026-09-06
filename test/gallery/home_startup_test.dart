import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/app.dart';
import 'package:rawviewer/core/platform_channels.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/rating_filter_button.dart';
import 'package:rawviewer/core/rating_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() {
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
    expect(find.byType(CheckboxListTile), findsNWidgets(8));
    await tester.tap(find.text('Thumbnail ratings'));
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
