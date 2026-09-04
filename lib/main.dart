import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final width = prefs.getDouble('window_width') ?? 1024.0;
    final height = prefs.getDouble('window_height') ?? 768.0;
    final x = prefs.getDouble('window_x');
    final y = prefs.getDouble('window_y');
    final isMaximized = prefs.getBool('window_maximized') ?? false;

    WindowOptions windowOptions = WindowOptions(
      size: Size(width, height),
      center: (x == null || y == null),
      title: 'Raw Viewer',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      if (isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const MyApp());
}
