import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/settings_page.dart';

const _systemState = FileAssociationSettings(
  supported: true,
  requiresSystemSettings: true,
  bindings: {'.jpg': false},
);

Widget _settings({
  required Future<void> Function() open,
  required Future<FileAssociationSettings> Function() refresh,
  ValueChanged<ViewerSettings>? onChanged,
  String locale = 'en',
}) {
  return MaterialApp(
    locale: Locale(locale),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPage(
      settings: const ViewerSettings(fileAssociations: _systemState),
      onClose: () {},
      onSettingsChanged: onChanged ?? (_) {},
      onOpenDefaultAppsSettings: open,
      onRefreshFileAssociations: refresh,
    ),
  );
}

/// Opens the System Integration category, where the association controls live.
///
/// The page renders a rail on wide viewports and a scrollable tab bar on narrow
/// ones; only one of the two keys is mounted at a time.
Future<void> _openIntegration(WidgetTester tester) async {
  const category = SettingsCategory.integration;
  final tile = find.byKey(ValueKey('settings-category-tile-${category.name}'));
  final tab = find.byKey(ValueKey('settings-category-tab-${category.name}'));
  final target = tester.any(tile) ? tile : tab;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The scrolling content list for the System Integration category.
Finder _integrationList() {
  return find.descendant(
    of: find.byKey(
      const PageStorageKey<String>('settings-category-integration'),
    ),
    matching: find.byType(Scrollable),
  );
}

void main() {
  for (final locale in ['en', 'zh']) {
    testWidgets('system association controls fit a narrow window in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var openCount = 0;
      ViewerSettings? updated;
      await tester.pumpWidget(_settings(
        locale: locale,
        open: () async {
          openCount++;
        },
        refresh: () async => _systemState,
        onChanged: (value) => updated = value,
      ));
      await tester.pumpAndSettle();
      await _openIntegration(tester);
      final button =
          find.byKey(const ValueKey('file-association-system-settings'));
      await tester.scrollUntilVisible(button, 250,
          scrollable: _integrationList());
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('file-association-enable-all')),
          findsNothing);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(openCount, 1);
      expect(updated!.fileAssociations.isBound('.jpg'), isFalse);
      final row = find.byKey(const ValueKey('file-association-.jpg'));
      await tester.scrollUntilVisible(row, 250, scrollable: _integrationList());
      await tester.pumpAndSettle();
      expect(find.descendant(of: row, matching: find.byType(Switch)),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('returning from system settings refreshes effective associations',
      (tester) async {
    var platformState = _systemState;
    ViewerSettings? updated;
    await tester.pumpWidget(_settings(
      open: () async {},
      refresh: () async => platformState,
      onChanged: (value) => updated = value,
    ));
    await tester.pumpAndSettle();
    await _openIntegration(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    platformState = _systemState.copyWith(bindings: {'.jpg': true});
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(updated!.fileAssociations.isBound('.jpg'), isTrue);
    final row = find.byKey(const ValueKey('file-association-.jpg'));
    await tester.scrollUntilVisible(row, 250, scrollable: _integrationList());
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: row, matching: find.byTooltip('Default: Raw Viewer')),
        findsOneWidget);
  });

  testWidgets(
      'a failed settings launch reports the error without changing defaults',
      (tester) async {
    ViewerSettings? updated;
    await tester.pumpWidget(_settings(
      open: () async => throw Exception('Launch failed'),
      refresh: () async => _systemState,
      onChanged: (value) => updated = value,
    ));
    await tester.pumpAndSettle();
    await _openIntegration(tester);
    final button =
        find.byKey(const ValueKey('file-association-system-settings'));
    await tester.scrollUntilVisible(button, 250,
        scrollable: _integrationList());
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Launch failed'), findsOneWidget);
    expect(updated, isNull);
  });
}
