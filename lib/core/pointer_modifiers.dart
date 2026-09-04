import 'dart:io';

import 'package:flutter/services.dart';

bool isZoomModifierPressed() {
  final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
  final isCtrlPressed = keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
      keysPressed.contains(LogicalKeyboardKey.controlRight);
  if (!Platform.isMacOS) {
    return isCtrlPressed;
  }

  return isCtrlPressed ||
      keysPressed.contains(LogicalKeyboardKey.metaLeft) ||
      keysPressed.contains(LogicalKeyboardKey.metaRight);
}
