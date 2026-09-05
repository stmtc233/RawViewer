import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/preferences_repository.dart';
import 'core/windows_startup.dart';

void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    // Build while preferences and native setup run, but keep the first frame
    // off screen until the saved bounds have been applied.
    binding.deferFirstFrame();
    final windowReady = _initializeWindowsWindow(binding);
    runApp(MyApp(desktopWindowReady: windowReady));
    await windowReady;
    return;
  }

  if (Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    final geometry =
        await const PreferencesRepository().loadWindowGeometry();

    WindowOptions windowOptions = WindowOptions(
      size: Size(geometry.width, geometry.height),
      center: !geometry.hasPosition,
      title: 'Raw Viewer',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (geometry.hasPosition) {
        await windowManager.setPosition(Offset(geometry.x!, geometry.y!));
      }
      if (geometry.isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}

Future<void> _initializeWindowsWindow(WidgetsBinding binding) async {
  late WindowGeometry geometry;
  try {
    geometry = await prepareWindowsWindow();
  } finally {
    binding.allowFirstFrame();
  }
  await showWindowsWindow(
    geometry: geometry,
    firstFrameRasterized: binding.waitUntilFirstFrameRasterized,
  );
}
