import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_timestamps.dart';
import 'package:rawviewer/core/raw_view_mode.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/media_group.dart';
import 'package:rawviewer/preview/image_preview_page.dart';
import 'package:rawviewer/preview/scroll_gesture_coalescer.dart';
import 'package:rawviewer/preview/single_image_preview.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/viewer_image.dart';

/// A signal cadence like the one a Windows touchpad driver produces for one
/// swipe: a small delta every frame or so.
Duration _burstTime(int index) => Duration(milliseconds: index * 10);

Widget _preview({
  required ValueChanged<int> onSwitchRequest,
  ScrollGestureCoalescer? scrollGesture,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SizedBox(
      width: 400,
      height: 300,
      child: SingleImagePreview(
        mediaGroup: const MediaGroup(
          primary: MediaFile(
            path: '/missing-test-image.jpg',
            kind: MediaKind.bitmap,
          ),
        ),
        thumbnailResizeWidth: 256,
        previewThumbnailResizeWidth: 512,
        imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
        settings: const ViewerSettings(),
        rotationQuarterTurns: 0,
        viewMode: RawViewMode.decodedRaw,
        onResetRotationRequested: () {},
        onSwitchRequest: onSwitchRequest,
        scrollGesture: scrollGesture ?? ScrollGestureCoalescer(),
        onTrackpadPanStart: (_) {},
        onTrackpadPanUpdate: (_) {},
        onTrackpadPanEnd: (_) {},
        onTrackpadPanCancel: () {},
        isActive: true,
        showPreviewOverview: false,
        overviewBottomInset: 0,
        isFastScrolling: ValueNotifier<bool>(false),
      ),
    ),
  );
}

/// Points a mouse at the preview so its scroll signals hit the image.
Future<TestPointer> _aimMouse(WidgetTester tester) async {
  final pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(find.byType(SingleImagePreview))),
  );
  return pointer;
}

Future<void> _scroll(
  WidgetTester tester,
  TestPointer pointer,
  Duration timeStamp,
  Offset delta,
) async {
  await tester.sendEventToBinding(
    pointer.scroll(delta, timeStamp: timeStamp),
  );
}

void main() {
  testWidgets('a flood of small scroll signals steps one image',
      (tester) async {
    final switches = <int>[];
    await tester.pumpWidget(_preview(onSwitchRequest: switches.add));
    await tester.pump();
    final pointer = await _aimMouse(tester);

    for (var i = 0; i < 8; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, 12));
    }
    expect(switches, [1]);

    // A second swipe after the gesture ended navigates again.
    for (var i = 10; i < 18; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, 12));
    }
    expect(switches, [1, 1]);
  });

  testWidgets('a long swipe keeps advancing past its first image',
      (tester) async {
    final switches = <int>[];
    await tester.pumpWidget(_preview(onSwitchRequest: switches.add));
    await tester.pump();
    final pointer = await _aimMouse(tester);

    for (var i = 0; i < 30; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, 12));
    }
    expect(switches.first, 1);
    expect(switches.reduce((a, b) => a + b), greaterThan(1));
  });

  testWidgets('discrete wheel notches still step once each', (tester) async {
    final switches = <int>[];
    await tester.pumpWidget(_preview(onSwitchRequest: switches.add));
    await tester.pump();
    final pointer = await _aimMouse(tester);

    for (var i = 0; i < 3; i++) {
      await _scroll(
        tester,
        pointer,
        Duration(milliseconds: 300 * i),
        const Offset(0, 100),
      );
    }
    expect(switches, [1, 1, 1]);
  });

  testWidgets('scroll signals during a trackpad page drag are ignored',
      (tester) async {
    final switches = <int>[];
    await tester.pumpWidget(_preview(onSwitchRequest: switches.add));
    await tester.pump();
    final pointer = await _aimMouse(tester);
    final location = tester.getCenter(find.byType(SingleImagePreview));

    final trackpad = TestPointer(2, PointerDeviceKind.trackpad);
    await tester.sendEventToBinding(trackpad.panZoomStart(location));
    await _scroll(tester, pointer, Duration.zero, const Offset(0, 100));
    expect(switches, isEmpty);

    await tester.sendEventToBinding(trackpad.panZoomEnd());
    await _scroll(
      tester,
      pointer,
      const Duration(milliseconds: 200),
      const Offset(0, 100),
    );
    expect(switches, [1]);
  });

  testWidgets('a zoom-modifier scroll flood applies a single zoom step',
      (tester) async {
    await tester.pumpWidget(_preview(onSwitchRequest: (_) {}));
    await tester.pump();
    final pointer = await _aimMouse(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    addTearDown(() => tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft));
    for (var i = 0; i < 8; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, -12));
    }
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.1, 0.0001));

    // A later gesture zooms once more.
    for (var i = 10; i < 18; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, -12));
    }
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1.21, 0.0001));
  });

  testWidgets('one swipe steps a single image across the page switch',
      (tester) async {
    const groups = [
      MediaGroup(
        primary: MediaFile(path: '/missing-1.jpg', kind: MediaKind.bitmap),
      ),
      MediaGroup(
        primary: MediaFile(path: '/missing-2.jpg', kind: MediaKind.bitmap),
      ),
      MediaGroup(
        primary: MediaFile(path: '/missing-3.jpg', kind: MediaKind.bitmap),
      ),
      MediaGroup(
        primary: MediaFile(path: '/missing-4.jpg', kind: MediaKind.bitmap),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImagePreviewPage(
          mediaGroups: groups,
          initialIndex: 0,
          thumbnailResizeWidth: 256,
          imageStore: ImageStore(LruCache<String, ViewerImage>(1024)),
          timestampRepository: TimestampRepository(),
          initialSettings: const ViewerSettings(),
          onClose: () {},
          onRawViewModeChanged: (_) {},
          onPreviewFilmstripHeightChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    // Aim inside the image area: the toolbar and the filmstrip overlay the
    // PageView and would consume the signal first.
    final pageRect = tester.getRect(find.byType(PageView));
    await tester.sendEventToBinding(
      pointer.hover(Offset(pageRect.center.dx, pageRect.top + 150)),
    );
    for (var i = 0; i < 8; i++) {
      await _scroll(tester, pointer, _burstTime(i), const Offset(0, 12));
    }
    await tester.pumpAndSettle();

    final pageView = tester.widget<PageView>(find.byType(PageView));
    expect(pageView.controller!.page, closeTo(1, 0.01));
  });
}
