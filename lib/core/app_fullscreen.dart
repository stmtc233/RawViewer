import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Puts the app into, or takes it out of, the platform's own full screen.
///
/// Desktop windows go full screen through `window_manager`; phones and
/// tablets hide the system bars instead. Failures are swallowed: full screen
/// is a nicety on top of the in-app immersive view, which works without it.
Future<void> setAppFullScreen(bool fullScreen) async {
  if (kIsWeb) return;
  try {
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      await windowManager.setFullScreen(fullScreen);
    } else if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    } else if (Platform.isIOS) {
      await SystemChrome.setEnabledSystemUIMode(
        fullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
        overlays: fullScreen ? null : SystemUiOverlay.values,
      );
    }
  } catch (_) {
    // No window to resize (tests, a closing window): the in-app view stands.
  }
}

/// Whether the desktop window is currently full screen.
Future<bool> isAppFullScreen() async {
  if (kIsWeb || !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    return false;
  }
  try {
    return await windowManager.isFullScreen();
  } catch (_) {
    return false;
  }
}
