import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/preferences_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
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
