import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/preview/preview_geometry.dart';
import 'package:rawviewer/preview/widgets/preview_filmstrip.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('restores filmstrip height and saves completed resize gestures',
      (tester) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final repo = const PreferencesRepository();
    await repo.savePreviewFilmstripHeight(180);
    final savedHeights = <double>[];
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
              ),
            ),
          ],
          initialIndex: 0,
          thumbnailResizeWidth: 256,
          imageStore: ImageStore(cache),
          timestampRepository: TimestampRepository(),
          initialSettings: ViewerSettings(
            previewFilmstripHeight: stored.previewFilmstripHeight,
          ),
          onClose: () {},
          onRawViewModeChanged: (_) {},
          onPreviewFilmstripHeightChanged: (height) {
            savedHeights.add(height);
            pendingSave = repo.savePreviewFilmstripHeight(height);
          },
        ),
      ));
      await tester.pumpAndSettle();
    }

    double displayedHeight() =>
        tester.widget<PreviewFilmstrip>(find.byType(PreviewFilmstrip)).height;
    final handle = find.byKey(
      const ValueKey('preview-filmstrip-resize-handle'),
    );

    await openPreview();
    expect(displayedHeight(), 180);
    final drag = await tester.startGesture(tester.getCenter(handle));
    await drag.moveBy(const Offset(0, -30));
    await tester.pump();
    await drag.moveBy(const Offset(0, -30));
    await tester.pump();
    final resizedHeight = displayedHeight();
    expect(resizedHeight, greaterThan(180));
    expect(savedHeights, isEmpty);
    await drag.up();
    await tester.pump();
    await pendingSave;
    expect(savedHeights, [resizedHeight]);
    expect((await repo.loadViewPreferences()).previewFilmstripHeight,
        resizedHeight);

    // Reopening uses the persisted value, not the former page's local state.
    await tester.pumpWidget(const SizedBox.shrink());
    await openPreview();
    expect(displayedHeight(), resizedHeight);

    tester.view.physicalSize = const Size(800, 360);
    await tester.pumpAndSettle();
    final smallWindowHeight = clampPreviewFilmstripHeight(
      height: resizedHeight,
      viewportHeight: 360,
      topInset: 0,
      bottomInset: 0,
    );
    expect(displayedHeight(), smallWindowHeight);
    expect(savedHeights, [resizedHeight]);
    expect((await repo.loadViewPreferences()).previewFilmstripHeight,
        resizedHeight);

    tester.view.physicalSize = const Size(800, 600);
    await tester.pumpAndSettle();
    expect(displayedHeight(), resizedHeight);

    // Drag from the visible edge even when the stored height exceeds the window.
    tester.view.physicalSize = const Size(800, 360);
    await tester.pumpAndSettle();
    final cancelledDrag = await tester.startGesture(tester.getCenter(handle));
    await cancelledDrag.moveBy(const Offset(0, 30));
    await tester.pump();
    await cancelledDrag.moveBy(const Offset(0, 30));
    await tester.pump();
    final smallerHeight = displayedHeight();
    expect(smallerHeight, lessThan(smallWindowHeight));
    expect(savedHeights, [resizedHeight]);
    await cancelledDrag.cancel();
    await tester.pump();
    await pendingSave;
    expect(savedHeights, [resizedHeight, smallerHeight]);

    await tester.pumpWidget(const SizedBox.shrink());
    await openPreview();
    expect(displayedHeight(), smallerHeight);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
