import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/exif_sidebar_settings.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'restores sidebar visibility, sections and completed width changes',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    const repo = PreferencesRepository();
    await repo.saveExifSidebarSettings(const ExifSidebarSettings(
      visible: true,
      width: 420,
      expandedSections: {ExifSection.file},
    ));
    final saves = <ExifSidebarSettings>[];
    Future<void>? pendingSave;
    final cache = LruCache<String, ViewerImage>(1024,
        onEvict: (_, image) => image.dispose());
    addTearDown(cache.clear);

    Future<void> openPreview() async {
      final stored = await repo.loadViewPreferences();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImagePreviewPage(
          mediaGroups: const [
            MediaGroup(
                primary: MediaFile(
              path: '/missing-test-image.jpg',
              kind: MediaKind.bitmap,
            ))
          ],
          initialIndex: 0,
          thumbnailResizeWidth: 256,
          imageStore: ImageStore(cache),
          timestampRepository: TimestampRepository(),
          initialSettings: ViewerSettings(exifSidebar: stored.exifSidebar),
          onClose: () {},
          onRawViewModeChanged: (_) {},
          onPreviewFilmstripHeightChanged: (_) {},
          onExifSidebarSettingsChanged: (settings) {
            saves.add(settings);
            pendingSave = repo.saveExifSidebarSettings(settings);
          },
        ),
      ));
      await tester.pump();
    }

    final panel = find.byKey(const ValueKey('preview-exif-sidebar'));
    final handle = find.byKey(const ValueKey('preview-exif-resize-handle'));
    double displayedWidth() => tester.getSize(panel).width;
    await openPreview();
    expect(displayedWidth(), 420);
    expect(find.text('/missing-test-image.jpg'), findsOneWidget);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(-30, 0));
    await tester.pump();
    await drag.moveBy(const Offset(-50, 0));
    await tester.pump();
    final resizedWidth = displayedWidth();
    expect(resizedWidth, greaterThan(420));
    expect(tester.getRect(find.byType(PageView)).right, 1200 - resizedWidth);
    expect(saves, isEmpty);
    await drag.up();
    await tester.pump();
    await pendingSave;
    expect(saves.single.width, resizedWidth);

    tester.view.physicalSize = const Size(360, 700);
    await tester.pump();
    expect(displayedWidth(), 336);
    expect(saves.length, 1);
    expect((await repo.loadViewPreferences()).exifSidebar.width, resizedWidth);
    tester.view.physicalSize = const Size(1200, 700);
    await tester.pump();
    expect(displayedWidth(), resizedWidth);

    final l10n =
        AppLocalizations.of(tester.element(find.byType(ImagePreviewPage)))!;
    await tester.tap(find.text(l10n.exifFileSection));
    await tester.pump();
    await pendingSave;
    expect(find.text('/missing-test-image.jpg'), findsNothing);
    expect(saves.last.expandedSections, isEmpty);
    await tester
        .tap(find.descendant(of: panel, matching: find.byIcon(Icons.close)));
    await tester.pump();
    await pendingSave;
    expect(panel, findsNothing);
    expect(saves.last.visible, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await openPreview();
    expect(panel, findsNothing);
    await tester.tap(find.byTooltip(l10n.showExifTooltip));
    await tester.pump();
    await pendingSave;
    expect(displayedWidth(), resizedWidth);
    expect(find.text('/missing-test-image.jpg'), findsNothing);
    expect(saves.last.visible, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await openPreview();
    expect(displayedWidth(), resizedWidth);

    // Cancelling a drag saves the final visible width just like the filmstrip.
    final cancelledDrag = await tester.startGesture(tester.getCenter(handle));
    await cancelledDrag.moveBy(const Offset(30, 0));
    await tester.pump();
    await cancelledDrag.moveBy(const Offset(30, 0));
    await tester.pump();
    final smallerWidth = displayedWidth();
    expect(smallerWidth, lessThan(resizedWidth));
    await cancelledDrag.cancel();
    await tester.pump();
    await pendingSave;
    expect(saves.last.width, smallerWidth);
    expect((await repo.loadViewPreferences()).exifSidebar.width, smallerWidth);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
