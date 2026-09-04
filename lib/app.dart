import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';

import 'core/preferences_repository.dart';
import 'home_page.dart';
import 'l10n/app_localizations.dart';
import 'settings_page.dart';
import 'ui/app_theme.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WindowListener {
  Locale? _locale;

  // Resize/move fire continuously while dragging; persist only once the user
  // settles instead of hitting the disk on every event.
  static const Duration _windowPersistDelay = Duration(milliseconds: 300);
  Timer? _windowGeometryTimer;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.addListener(this);
    }
  }

  @override
  void dispose() {
    _windowGeometryTimer?.cancel();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  void _scheduleWindowGeometrySave() {
    _windowGeometryTimer?.cancel();
    _windowGeometryTimer = Timer(_windowPersistDelay, _persistWindowGeometry);
  }

  Future<void> _persistWindowGeometry() async {
    try {
      if (await windowManager.isMaximized()) return;

      final size = await windowManager.getSize();
      final position = await windowManager.getPosition();
      await const PreferencesRepository().saveWindowBounds(
        width: size.width,
        height: size.height,
        x: position.dx,
        y: position.dy,
      );
    } catch (_) {
      // Window may already be gone; losing geometry is not worth surfacing.
    }
  }

  @override
  void onWindowResized() {
    _scheduleWindowGeometrySave();
  }

  @override
  void onWindowMoved() {
    _scheduleWindowGeometrySave();
  }

  @override
  void onWindowMaximize() async {
    await const PreferencesRepository().saveWindowMaximized(true);
  }

  @override
  void onWindowUnmaximize() async {
    await const PreferencesRepository().saveWindowMaximized(false);
  }

  void _handleAppLanguageChanged(AppLanguage language) {
    setState(() {
      _locale = language.locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        locale: _locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('en'),
          Locale('zh'),
        ],
        theme: rawViewerTheme,
        home: HomePage(onAppLanguageChanged: _handleAppLanguageChanged),
      ),
    );
  }
}
