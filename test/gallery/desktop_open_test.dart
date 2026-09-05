import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/app.dart';
import 'package:rawviewer/core/platform_channels.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory directory;
  late File first;
  late File second;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('rawviewer-open-test-');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
    );
    first = File('${directory.path}/a.png')..writeAsBytesSync(bytes);
    second = File('${directory.path}/b.png')..writeAsBytesSync(bytes);
  });

  tearDown(() {
    desktopOpenChannel.setMethodCallHandler(null);
    directory.deleteSync(recursive: true);
  });

  Future<void> openPaths(WidgetTester tester, List<String> paths) async {
    final completed = Completer<void>();
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      desktopOpenChannel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('openPaths', paths)),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  testWidgets('second desktop open replaces the current preview',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await openPaths(tester, [first.path]);
    await tester.pumpAndSettle();
    final oldPreview =
        tester.widget<ImagePreviewPage>(find.byType(ImagePreviewPage));
    expect(oldPreview.mediaGroups.single.primary.path, first.path);

    await openPaths(tester, [second.path]);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsOneWidget);
    expect(
        tester
            .widget<ImagePreviewPage>(find.byType(ImagePreviewPage))
            .mediaGroups
            .single
            .primary
            .path,
        second.path);
    // An old route must not load a new source's directory or close its preview.
    expect(await oldPreview.onLoadDirectory!(), isNull);
    oldPreview.onClose();
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsOneWidget);

    tester.widget<ImagePreviewPage>(find.byType(ImagePreviewPage)).onClose();
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('rapid desktop opens keep only the latest preview',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await openPaths(tester, [first.path]);
    await openPaths(tester, [second.path]);
    await openPaths(tester, [second.path]);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage, skipOffstage: false), findsOneWidget);
    expect(
        tester
            .widget<ImagePreviewPage>(find.byType(ImagePreviewPage))
            .mediaGroups
            .single
            .primary
            .path,
        second.path);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('opening a directory dismisses an existing single-file preview',
      (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    await openPaths(tester, [first.path]);
    await tester.pumpAndSettle();
    await openPaths(tester, [directory.path]);
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewPage), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
