import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'preferences_repository.dart';

/// Restores a new, hidden Windows window before Flutter submits its first frame.
Future<WindowGeometry> prepareWindowsWindow() async {
  late WindowGeometry geometry;
  await Future.wait<void>([
    windowManager.ensureInitialized(),
    const PreferencesRepository().loadWindowGeometry().then((value) {
      geometry = value;
    }),
  ]);

  // A newly created runner window is already normal, hidden and resizable.
  // waitUntilReadyToShow also initialises unused taskbar APIs and resets
  // window states; none of those operations are needed for this startup path.
  await Future.wait<void>([
    windowManager.setBounds(
      null,
      size: Size(geometry.width, geometry.height),
      position: geometry.hasPosition ? Offset(geometry.x!, geometry.y!) : null,
    ),
    windowManager.setTitle('Raw Viewer'),
  ]);
  if (!geometry.hasPosition) {
    await windowManager.center();
  }
  return geometry;
}

/// The runner leaves the window hidden; Dart shows it only after a real frame.
Future<void> showWindowsWindow({
  required WindowGeometry geometry,
  required Future<void> firstFrameRasterized,
}) async {
  await firstFrameRasterized;
  if (geometry.isMaximized) {
    await windowManager.maximize();
  }
  await windowManager.show();
}
