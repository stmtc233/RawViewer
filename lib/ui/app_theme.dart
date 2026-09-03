import 'package:flutter/material.dart';

abstract final class RawViewerColors {
  static const canvas = Color(0xFF121416);
  static const surface = Color(0xFF191C20);
  static const raisedSurface = Color(0xFF20242A);
  static const border = Color(0xFF30363D);
  static const mutedBorder = Color(0xFF272C31);
  static const text = Color(0xFFF0F3F5);
  static const mutedText = Color(0xFF9BA6B2);
  static const accent = Color(0xFF59B8A7);
  static const accentMuted = Color(0xFF1F4B46);
  static const danger = Color(0xFFE18C87);
}

final ThemeData rawViewerTheme = ThemeData(
  useMaterial3: false,
  brightness: Brightness.dark,
  fontFamily: 'NotoSansSC',
  scaffoldBackgroundColor: RawViewerColors.canvas,
  colorScheme: const ColorScheme.dark(
    primary: RawViewerColors.accent,
    onPrimary: Color(0xFF061A17),
    secondary: RawViewerColors.accent,
    onSecondary: Color(0xFF061A17),
    surface: RawViewerColors.surface,
    onSurface: RawViewerColors.text,
    error: RawViewerColors.danger,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: RawViewerColors.surface,
    foregroundColor: RawViewerColors.text,
    elevation: 0,
    centerTitle: false,
    toolbarHeight: 48,
    titleTextStyle: TextStyle(
      color: RawViewerColors.text,
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
  ),
  dividerTheme: const DividerThemeData(
    color: RawViewerColors.border,
    thickness: 1,
    space: 1,
  ),
  iconTheme: const IconThemeData(
    color: RawViewerColors.mutedText,
    size: 20,
  ),
  tooltipTheme: const TooltipThemeData(
    decoration: BoxDecoration(
      color: Color(0xFFF0F3F5),
      borderRadius: BorderRadius.all(Radius.circular(4)),
    ),
    textStyle: TextStyle(color: Color(0xFF16191D), fontSize: 12),
    waitDuration: Duration(milliseconds: 450),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: RawViewerColors.surface,
    elevation: 24,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(6)),
      side: BorderSide(color: RawViewerColors.border),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: RawViewerColors.raisedSurface,
    contentTextStyle: TextStyle(color: RawViewerColors.text),
    behavior: SnackBarBehavior.floating,
  ),
  switchTheme: SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? RawViewerColors.accent
          : RawViewerColors.mutedText,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? RawViewerColors.accentMuted
          : RawViewerColors.mutedBorder,
    ),
  ),
  sliderTheme: const SliderThemeData(
    activeTrackColor: RawViewerColors.accent,
    inactiveTrackColor: RawViewerColors.border,
    thumbColor: RawViewerColors.text,
    overlayColor: Color(0x3359B8A7),
    trackHeight: 2,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
  ),
);
