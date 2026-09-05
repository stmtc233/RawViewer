import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/preferences_repository.dart';
import 'package:rawviewer/core/windows_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const screenChannel =
      MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel,
        (call) async {
      calls.add(call);
      if (call.method == 'isMinimized') return false;
      if (call.method == 'getBounds') {
        return {'x': 0.0, 'y': 0.0, 'width': 1024.0, 'height': 768.0};
      }
      return null;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(screenChannel, null);
  });

  test('restores saved bounds without showing or resetting the window',
      () async {
    SharedPreferences.setMockInitialValues({
      'window_width': 1200.0,
      'window_height': 800.0,
      'window_x': -1200.0,
      'window_y': 60.0,
      'window_maximized': true,
    });

    final geometry = await prepareWindowsWindow();

    expect(geometry.isMaximized, isTrue);
    expect(calls.map((call) => call.method),
        ['ensureInitialized', 'setBounds', 'setTitle']);
    final bounds = calls[1].arguments as Map;
    expect(bounds['width'], 1200.0);
    expect(bounds['height'], 800.0);
    expect(bounds['x'], -1200.0);
    expect(bounds['y'], 60.0);
    expect(calls[2].arguments, {'title': 'Raw Viewer'});
  });

  test('centers a first-launch window in the monitor work area', () async {
    const display = {
      'id': 'primary',
      'size': {'width': 1920.0, 'height': 1080.0},
      'visibleSize': {'width': 1920.0, 'height': 1040.0},
      'visiblePosition': {'dx': 0.0, 'dy': 0.0},
    };
    binding.defaultBinaryMessenger.setMockMethodCallHandler(screenChannel,
        (call) async {
      return switch (call.method) {
        'getPrimaryDisplay' => display,
        'getAllDisplays' => {
            'displays': [display],
          },
        'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
        _ => throw StateError('Unexpected screen call: ${call.method}'),
      };
    });

    final geometry = await prepareWindowsWindow();

    expect(geometry.hasPosition, isFalse);
    final bounds = calls.where((call) => call.method == 'setBounds').toList();
    expect(bounds, hasLength(2));
    expect((bounds.first.arguments as Map)['width'], 1024.0);
    expect((bounds.first.arguments as Map)['height'], 768.0);
    expect((bounds.last.arguments as Map)['x'], 448.0);
    expect((bounds.last.arguments as Map)['y'], 136.0);
    expect(calls.any((call) => call.method == 'show'), isFalse);
  });

  for (final maximized in [false, true]) {
    test('waits for rasterization before showing (maximized: $maximized)',
        () async {
      final frame = Completer<void>();
      final shown = showWindowsWindow(
        geometry: WindowGeometry(
          width: 1024,
          height: 768,
          isMaximized: maximized,
        ),
        firstFrameRasterized: frame.future,
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
      frame.complete();
      await shown;

      expect(calls.map((call) => call.method), [
        if (maximized) 'maximize',
        'isMinimized',
        'show',
      ]);
    });
  }
}
