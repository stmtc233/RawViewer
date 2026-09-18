import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_types.dart';
import 'package:rawviewer/settings_page.dart';

/// Reads the `[start, end)` slice of [path] so the parsers below only ever see
/// the list they are meant to check.
///
/// The platform lists are the only place a format can be lost silently: one the
/// app displays but never registers simply never appears in the system's "open
/// with" list, with nothing to report. These tests read the platform sources
/// directly so that adding a format to one place and forgetting another fails
/// here instead.
String _section(String path, Pattern start, Pattern end) {
  final source = File(path).readAsStringSync();
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: '$path no longer contains $start');
  final to = source.indexOf(end, from);
  expect(to, isNonNegative, reason: '$path no longer contains $end');
  return source.substring(from, to);
}

List<String> _extensions(String text, RegExp pattern) =>
    pattern.allMatches(text).map((match) => '.${match.group(1)}').toList();

void main() {
  test('parses platform association state for every supported extension', () {
    final state = FileAssociationSettings.fromPlatformMap({
      'supported': true,
      'bindings': {
        '.arw': true,
        '.jpg': false,
      },
    });

    expect(state.supported, isTrue);
    expect(state.requiresSystemSettings, isFalse);
    expect(state.isBound('.arw'), isTrue);
    expect(state.isBound('.jpg'), isFalse);
    expect(state.bindings.keys, containsAll(supportedExtensions));
    expect(state.isBound('.unsupported'), isFalse);
  });

  test('missing platform bindings default to unbound', () {
    final state = FileAssociationSettings.fromPlatformMap({
      'supported': true,
    });

    expect(state.bindings, isEmpty);
    expect(state.isBound('.arw'), isFalse);
  });

  test('preserves the system-managed association capability', () {
    final state = FileAssociationSettings.fromPlatformMap({
      'supported': true,
      'requiresSystemSettings': true,
      'bindings': {'.jpg': false},
    });
    expect(state.requiresSystemSettings, isTrue);
    expect(state.copyWith(bindings: {'.jpg': true}).requiresSystemSettings,
        isTrue);
    expect(state.isBound('.jpg'), isFalse);
  });

  test('macOS binds exactly the supported extensions', () {
    final contentTypes = _section(
      'macos/Runner/FileAssociations.swift',
      'static let contentTypes = [',
      ']',
    );
    final types = <String, String>{
      for (final match
          in RegExp(r'^\s+"([a-z0-9]+)": "([^"]+)"', multiLine: true)
              .allMatches(contentTypes))
        '.${match.group(1)}': match.group(2)!,
    };
    expect(types.keys.toSet(), supportedExtensions.toSet());

    // Launch Services cannot bind a type the bundle does not declare, so the
    // document types have to grow with the map above.
    final documentTypes = _section(
      'macos/Runner/Info.plist',
      '<key>CFBundleDocumentTypes</key>',
      '<key>UTImportedTypeDeclarations</key>',
    );
    for (final type in types.values) {
      expect(documentTypes, contains('<string>$type</string>'));
    }
  });

  test('Windows registers exactly the supported extensions', () {
    final source =
        File('windows/runner/shell_integration.cpp').readAsStringSync();
    final declaredSize = RegExp(r'constexpr std::array<const wchar_t\*, (\d+)>')
        .firstMatch(source)
        ?.group(1);
    expect(declaredSize, isNotNull);
    final extensions = _extensions(
      _section('windows/runner/shell_integration.cpp',
          'kFileAssociationExtensions = {{', '}};'),
      RegExp(r'L"([a-z0-9]+)"'),
    );
    expect(extensions.toSet(), supportedExtensions.toSet());
    expect(extensions.length, supportedExtensions.length,
        reason: 'an extension is registered twice');
    expect(int.parse(declaredSize!), extensions.length,
        reason: 'the declared array size no longer matches its entries');

    // The installer writes the same registry entries at install time.
    final installer = _extensions(
      _section('innosetup/rawviewer.iss', '[Registry]', '[Run]'),
      RegExp(r'ValueName: "\.([a-z0-9]+)"; ValueData: "RawViewer\.'),
    );
    expect(installer.toSet(), supportedExtensions.toSet());
    expect(installer.length, supportedExtensions.length,
        reason: 'an extension is registered twice');
  });
}
