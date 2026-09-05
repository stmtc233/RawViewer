import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/media_types.dart';
import 'package:rawviewer/settings_page.dart';

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
}
