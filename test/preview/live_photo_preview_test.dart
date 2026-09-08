import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/live_photo.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/preview/widgets/live_photo_preview.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _VideoPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final sources = <DataSource>[];
  final firstCreated = Completer<void>();
  int created = 0;
  int disposed = 0;
  int played = 0;
  int paused = 0;
  int rewound = 0;
  double volume = 1;
  Duration position = Duration.zero;
  Completer<void>? seekGate;

  StreamController<VideoEvent> get events => streams[created]!;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    streams[++created] = StreamController<VideoEvent>.broadcast();
    sources.add(options.dataSource);
    if (!firstCreated.isCompleted) firstCreated.complete();
    return created;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;
  @override
  Future<void> dispose(int playerId) async {
    disposed++;
  }

  @override
  Future<void> play(int playerId) async {
    played++;
  }

  @override
  Future<void> pause(int playerId) async {
    paused++;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    if (position == Duration.zero) {
      rewound++;
      await seekGate?.future;
    }
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildView(int playerId) => const SizedBox(key: ValueKey('movie'));
  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
      int playerId, bool preventsDisplaySleepDuringVideoPlayback) async {}

  void initialize() => events.add(VideoEvent(
      eventType: VideoEventType.initialized,
      size: const Size(200, 100),
      duration: const Duration(seconds: 3)));
}

void main() {
  late _VideoPlatform platform;
  setUp(() {
    platform = _VideoPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() async {
    for (final stream in platform.streams.values) {
      await stream.close();
    }
  });

  const source = LivePhotoSource('/photo.mov', length: 32);
  Widget preview(
          {bool active = true,
          bool longPressEnabled = false,
          String path = '/photo.jpg',
          Future<LivePhotoSource?> Function(String)? loader}) =>
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: LivePhotoPreview(
          filePath: path,
          active: active,
          longPressPlaybackEnabled: longPressEnabled,
          quarterTurns: 0,
          bottomInset: 0,
          sourceLoader: loader ?? (_) async => source,
          child: const ColoredBox(
              key: ValueKey('still'), color: Colors.transparent),
        )),
      );

  Finder getFade() => find.ancestor(
      of: find.byKey(const ValueKey('movie')),
      matching: find.byType(AnimatedOpacity));

  Future<void> ready(WidgetTester tester,
      {bool longPressEnabled = false}) async {
    await tester.pumpWidget(preview(longPressEnabled: longPressEnabled));
    await tester.pump();
    platform.initialize();
    await tester.pump();
    await tester.pump();
  }

  Future<void> release(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {});
  }

  testWidgets('prepares the active photo without starting playback',
      (tester) async {
    await ready(tester);
    expect(platform.created, 1);
    expect(platform.played, 0);
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 0);
    await release(tester);
    expect(platform.disposed, 1);
  });

  testWidgets('ignores stale discovery and does not prepare inactive pages',
      (tester) async {
    final result = Completer<LivePhotoSource?>();
    await tester.pumpWidget(preview(loader: (_) => result.future));
    await tester.pumpWidget(preview(active: false));
    result.complete(source);
    await tester.pump();
    expect(platform.created, 0);
    expect(find.byTooltip('Play Live Photo'), findsNothing);
    await tester.pumpWidget(preview(loader: (_) async => null));
    await tester.pump();
    expect(platform.created, 0);
    final next = Completer<LivePhotoSource?>();
    await tester
        .pumpWidget(preview(path: '/next.jpg', loader: (_) => next.future));
    await release(tester);
    next.complete(source);
    await tester.pump();
    expect(platform.created, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press playback is disabled by default', (tester) async {
    await ready(tester);
    await tester.longPress(find.byKey(const ValueKey('still')));
    await tester.pump();
    expect(platform.played, 0);
    await release(tester);
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('holding with $kind reuses the player after release',
        (tester) async {
      await ready(tester, longPressEnabled: true);
      for (var i = 1; i <= 2; i++) {
        final press = await tester.startGesture(
            tester.getCenter(find.byKey(const ValueKey('still'))),
            kind: kind);
        await tester.pump(const Duration(seconds: 1));
        expect(platform.played, i);
        await press.up();
        await tester.pump();
        expect(platform.created, 1);
        expect(platform.disposed, 0);
        expect(platform.rewound, i);
        expect(find.byTooltip('Play Live Photo'), findsOneWidget);
      }
      await release(tester);
      expect(platform.disposed, 1);
    });
  }

  testWidgets(
      'releasing during preparation cancels playback but keeps preparation',
      (tester) async {
    await tester.pumpWidget(preview(longPressEnabled: true));
    await tester.pump();
    final press = await tester
        .startGesture(tester.getCenter(find.byKey(const ValueKey('still'))));
    await tester.pump(const Duration(seconds: 1));
    await press.up();
    await tester.pump();
    platform.initialize();
    await tester.pump();
    expect(platform.played, 0);
    expect(platform.created, 1);
    expect(platform.disposed, 0);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.played, 1);
    await release(tester);
  });

  testWidgets('short taps and releasing a hold do not stop button playback',
      (tester) async {
    await ready(tester, longPressEnabled: true);
    await tester.tap(find.byKey(const ValueKey('still')));
    await tester.pump();
    expect(platform.played, 0);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    await tester.longPress(find.byKey(const ValueKey('still')));
    await tester.pump();
    expect(find.byTooltip('Stop Live Photo'), findsOneWidget);
    expect(platform.rewound, 0);
    await release(tester);
  });

  testWidgets(
      'completion rewinds and replay does not initialize or wait for a position poll',
      (tester) async {
    await ready(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    platform.position = const Duration(milliseconds: 100);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 1);
    platform.events.add(VideoEvent(eventType: VideoEventType.completed));
    await tester.pump();
    expect(platform.rewound, 1);
    expect(platform.position, Duration.zero);
    expect(platform.disposed, 0);
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 0);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.played, 2);
    expect(platform.created, 1);
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 1);
    await release(tester);
    expect(platform.disposed, 1);
  });

  testWidgets(
      'replay waits for an outstanding rewind and stop cancels queued play',
      (tester) async {
    await ready(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    platform.seekGate = Completer<void>();
    await tester.tap(find.byTooltip('Stop Live Photo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.played, 1);
    await tester.tap(find.byTooltip('Stop Live Photo'));
    await tester.pump();
    platform.seekGate!.complete();
    await tester.pump();
    expect(platform.played, 1);
    expect(platform.created, 1);
    await release(tester);
  });

  testWidgets('sound is selectable before playback and retained for replay',
      (tester) async {
    await ready(tester);
    await tester.tap(find.byTooltip('Unmute Live Photo'));
    await tester.pump();
    expect(platform.played, 0);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.volume, 1);
    await tester.tap(find.byTooltip('Stop Live Photo'));
    await tester.pump();
    expect(find.byTooltip('Mute Live Photo'), findsOneWidget);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.volume, 1);
    expect(platform.created, 1);
    await release(tester);
  });

  testWidgets(
      'keeps the still during first startup and preserves the background',
      (tester) async {
    await ready(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 0);
    platform.events.add(VideoEvent(eventType: VideoEventType.bufferingStart));
    platform.position = const Duration(milliseconds: 100);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 0);
    platform.events.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(getFade()).opacity, 1);
    expect(
        find.ancestor(
            of: find.byKey(const ValueKey('movie')),
            matching: find.byWidgetPredicate((widget) =>
                widget is ColoredBox && widget.color == Colors.black)),
        findsNothing);
    await release(tester);
  });

  testWidgets('leaving during preparation releases without starting playback',
      (tester) async {
    await tester.pumpWidget(preview());
    await tester.pump();
    await tester.pumpWidget(preview(active: false));
    platform.initialize();
    await tester.pump();
    await tester.runAsync(() async {});
    expect(platform.disposed, 1);
    expect(platform.played, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background preparation errors remain quiet and button retries',
      (tester) async {
    await tester.pumpWidget(preview());
    await tester.pump();
    platform.events.addError(
        PlatformException(code: 'decode_failed', message: 'Invalid video'));
    await tester.pump();
    await tester.runAsync(() async {});
    expect(platform.disposed, 1);
    expect(find.text('Unable to play this Live Photo'), findsNothing);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    expect(platform.created, 2);
    platform.initialize();
    await tester.pump();
    expect(platform.played, 1);
    platform.events.addError(
        PlatformException(code: 'decode_failed', message: 'Invalid video'));
    await tester.pump();
    await tester.runAsync(() async {});
    expect(platform.disposed, 2);
    expect(find.text('Unable to play this Live Photo'), findsOneWidget);
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
  });

  testWidgets('backgrounding releases and resuming prepares without autoplay',
      (tester) async {
    await ready(tester);
    await tester.tap(find.byTooltip('Play Live Photo'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.runAsync(() async {});
    expect(platform.disposed, 1);
    expect(find.byKey(const ValueKey('movie')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(platform.created, 2);
    platform.initialize();
    await tester.pump();
    expect(platform.played, 1);
    expect(find.byTooltip('Play Live Photo'), findsOneWidget);
    await release(tester);
  });

  testWidgets('embedded video is extracted once and kept only until leaving',
      (tester) async {
    late Directory directory;
    late File photo;
    late File extracted;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('live-replay-test-');
      photo = await File('${directory.path}/motion.jpg')
          .writeAsBytes(List<int>.generate(32, (i) => i));
      await tester.pumpWidget(preview(
          loader: (_) async =>
              LivePhotoSource(photo.path, offset: 16, length: 16)));
      await platform.firstCreated.future;
      extracted = File.fromUri(Uri.parse(platform.sources.single.uri!));
      expect(
          await extracted.readAsBytes(), List<int>.generate(16, (i) => i + 16));
    });
    addTearDown(() => directory.delete(recursive: true));
    platform.initialize();
    await tester.pump();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Play Live Photo'));
      await tester.pump();
      await tester.tap(find.byTooltip('Stop Live Photo'));
      await tester.pump();
    }
    expect(platform.created, 1);
    await tester.runAsync(() async {
      expect(await extracted.exists(), isTrue);
    });
    await release(tester);
    // Filesystem completions arrive outside the fake frame scheduler.
    for (var i = 0; i < 100 && extracted.existsSync(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.runAsync(() async {
      // Native disposal precedes asynchronous filesystem cleanup.
      expect(platform.disposed, 1);
      expect(await extracted.exists(), isFalse);
      expect(await photo.exists(), isTrue);
    });
  });
}
