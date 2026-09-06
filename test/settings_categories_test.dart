import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/app_info.dart';
import 'package:rawviewer/core/media_types.dart';
import 'package:rawviewer/core/update_checker.dart';
import 'package:rawviewer/l10n/app_localizations.dart';
import 'package:rawviewer/settings_page.dart';
import 'package:rawviewer/ui/desktop_controls.dart';

const _appInfo = AppInfo(version: '1.2.0', buildNumber: '42');

Widget _page({
  ViewerSettings settings = const ViewerSettings(),
  Future<FileAssociationSettings> Function(Set<String>)? onAssociationsChanged,
  AppInfoLoader? appInfoLoader,
  Future<String> Function()? latestTagFetcher,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: SettingsPage(
      settings: settings,
      onClose: () {},
      onSettingsChanged: (_) {},
      onFileAssociationsChanged: onAssociationsChanged,
      appInfoLoader: appInfoLoader ?? () async => _appInfo,
      latestTagFetcher: latestTagFetcher ?? () async => 'v1.2.0',
    ),
  );
}

Finder _tile(SettingsCategory category) =>
    find.byKey(ValueKey('settings-category-tile-${category.name}'));

Finder _tab(SettingsCategory category) =>
    find.byKey(ValueKey('settings-category-tab-${category.name}'));

Future<void> _open(WidgetTester tester, SettingsCategory category) async {
  final target = tester.any(_tile(category)) ? _tile(category) : _tab(category);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  group('category navigation', () {
    testWidgets('a wide viewport shows the rail, not the tab bar',
        (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(_tile(SettingsCategory.general), findsOneWidget);
      expect(_tab(SettingsCategory.general), findsNothing);
    });

    testWidgets('a narrow viewport shows a horizontally scrollable tab bar',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(_tab(SettingsCategory.general), findsOneWidget);
      expect(_tile(SettingsCategory.general), findsNothing);

      // The tabs must scroll rather than overflow the 360px viewport.
      final tabRow = find.ancestor(
        of: _tab(SettingsCategory.general),
        matching: find.byType(SingleChildScrollView),
      );
      expect(tabRow, findsOneWidget);
      expect(
        tester.widget<SingleChildScrollView>(tabRow.first).scrollDirection,
        Axis.horizontal,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sections land in the category that owns them', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      // General opens first and owns language + time display.
      expect(find.byKey(const ValueKey('grid-aspect-adaptive')), findsNothing);

      await _open(tester, SettingsCategory.appearance);
      expect(find.byKey(const ValueKey('grid-aspect-adaptive')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('page-switch-animation')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('preview-toolbar-opacity')),
        findsOneWidget,
      );

      await _open(tester, SettingsCategory.about);
      expect(find.byKey(const ValueKey('about-version')), findsOneWidget);
    });

    testWidgets('the integration category is hidden without a platform hook',
        (tester) async {
      // No context-menu or association handler is wired, so the category would
      // open onto nothing.
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();

      expect(_tile(SettingsCategory.integration), findsNothing);
      expect(_tab(SettingsCategory.integration), findsNothing);
    });

    testWidgets('the integration category appears once associations are wired',
        (tester) async {
      await tester.pumpWidget(_page(
        settings: ViewerSettings(
          fileAssociations: FileAssociationSettings(
            supported: true,
            bindings: {
              for (final extension in supportedExtensions) extension: false,
            },
          ),
        ),
        onAssociationsChanged: (_) async => const FileAssociationSettings(
          supported: true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(_tile(SettingsCategory.integration), findsOneWidget);
    });
  });

  group('about page', () {
    testWidgets('shows the running build version', (tester) async {
      await tester.pumpWidget(_page());
      await tester.pumpAndSettle();
      await _open(tester, SettingsCategory.about);

      expect(find.text('1.2.0 (build 42)'), findsOneWidget);
    });

    testWidgets('reports when a newer release exists', (tester) async {
      await tester.pumpWidget(_page(latestTagFetcher: () async => 'v1.5.0'));
      await tester.pumpAndSettle();
      await _open(tester, SettingsCategory.about);

      await tester.tap(find.byKey(const ValueKey('about-check-updates-button')));
      await tester.pumpAndSettle();

      expect(find.text('New version v1.5.0 available'), findsOneWidget);
    });

    testWidgets('reports being up to date', (tester) async {
      await tester.pumpWidget(_page(latestTagFetcher: () async => 'v1.2.0'));
      await tester.pumpAndSettle();
      await _open(tester, SettingsCategory.about);

      await tester.tap(find.byKey(const ValueKey('about-check-updates-button')));
      await tester.pumpAndSettle();

      expect(find.text('You are on the latest version'), findsOneWidget);
    });

    testWidgets('surfaces a rate limit as its own message', (tester) async {
      await tester.pumpWidget(_page(
        latestTagFetcher: () async => throw const UpdateHttpStatusException(403),
      ));
      await tester.pumpAndSettle();
      await _open(tester, SettingsCategory.about);

      await tester.tap(find.byKey(const ValueKey('about-check-updates-button')));
      await tester.pumpAndSettle();

      expect(
        find.text('GitHub rate limit reached. Try again later.'),
        findsOneWidget,
      );
    });

    testWidgets('stays usable when the version cannot be read', (tester) async {
      await tester.pumpWidget(_page(
        appInfoLoader: () async => throw Exception('no platform channel'),
      ));
      await tester.pumpAndSettle();
      await _open(tester, SettingsCategory.about);

      expect(find.text('Reading version…'), findsOneWidget);
      // Without a known version there is nothing to compare against, so the
      // check is disabled rather than reporting a bogus result.
      final button = tester.widget<DesktopCommandButton>(
        find.byKey(const ValueKey('about-check-updates-button')),
      );
      expect(button.onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  });
}