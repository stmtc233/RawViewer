# Agent Guide

## Project Overview

Raw Viewer is a Flutter application for browsing RAW and standard image files.
Dart code provides the UI, caching, metadata handling, and worker orchestration,
while native C++ wrappers expose LibRaw through Dart FFI.

## Repository Layout

- `lib/`: application code and generated localization bindings.
- `lib/l10n/`: English and Chinese ARB localization sources.
- `test/`: Flutter unit and widget tests.
- `tool/`: developer utilities, including native decode checks.
- `android/`, `ios/`, `linux/`, `macos/`, `windows/`: platform projects and
  native integration code.
- `android/app/src/main/cpp/libraw/` and `windows/native_lib/libraw/`: vendored
  LibRaw source snapshots. Keep these trees aligned with their upstream source.

## Development Workflow

Run these commands from the repository root:

```bash
flutter pub get
flutter analyze
flutter test
```

When changing platform or native code, also build the affected target when the
required toolchain is available:

```bash
flutter build android --release
flutter build linux --release
flutter build macos --release
flutter build windows --release
```

## Change Guidelines

- Follow the existing Dart and Flutter patterns before introducing new
  abstractions or dependencies.
- Prefer the newer compatible version when resolving dependency version
  conflicts or compatibility issues. Keep dependencies and toolchain versions
  current where practical, while preserving supported-platform compatibility.
- Keep UI work responsive by leaving RAW decoding and other expensive work off
  the main isolate.
- Update both `lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` for user-facing
  text, then regenerate localization bindings through the normal Flutter flow.
- Do not edit generated build output or files ignored by `.gitignore`.
- Avoid modifying vendored LibRaw files unless the task explicitly requires an
  upstream update or patch.
- Preserve behavior across Windows, macOS, Linux, Android, and iOS. Guard
  platform-specific code and validate the affected platform integration.
- Treat C and C++ native changes as cross-platform changes: update every
  corresponding platform implementation together, unless a platform has no
  equivalent integration. Document and confirm any intentional exception.
- Add focused tests for behavior changes and run `flutter analyze` and
  `flutter test` before committing.

## Completion and Collaboration

- Do not consider a task complete until the applicable checks have passed.
  At minimum, run `flutter analyze` and `flutter test` for Dart or Flutter
  changes; also run relevant platform builds for native or platform changes
  when the required toolchain is available.
- When a requirement, tradeoff, or intended behavior needs confirmation, ask
  the user before choosing an implementation. Do not make that decision
  unilaterally.
- When resolving multiple independent problems, keep their changes and Git
  commits separate so each commit addresses one coherent problem.
