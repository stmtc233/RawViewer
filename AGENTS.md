# Agent Guide

## Project Overview

Raw Viewer is a Flutter application for browsing RAW and standard image files.
Dart code provides the UI, caching, metadata handling, and worker orchestration,
while native C++ wrappers expose LibRaw through Dart FFI.

## Repository Layout

```
lib/
  main.dart              App bootstrap and desktop window setup
  app.dart               MyApp widget, window geometry persistence
  home_page.dart         HomePage and gallery state (_HomePageState)
  settings_page.dart     ViewerSettings model and SettingsPage widget

  core/
    decode_target.dart         kDecodeWidthBucket, bucketDecodeWidth
    media_timestamps.dart      MediaTimestampInfo, TimestampRepository, EXIF
    media_types.dart           rawExtensions / bitmapExtensions / supportedExtensions,
                               embeddedJpegExportFileName
    platform_channels.dart     desktopOpenChannel, windowsShellChannel
    pointer_modifiers.dart     isZoomModifierPressed
    preferences_repository.dart  PreferencesRepository — all SharedPreferences keys

  gallery/
    grid_zoom_accumulator.dart  GridZoomAccumulator — scroll + pinch → column delta
    media_library.dart          listMediaFilesInDirectory, mediaFileFromPath,
                                deduplicateMediaFiles
    widgets/
      desktop_command_bar.dart   DesktopCommandBar, GalleryActionsMenu, ThumbnailSizeControls
      gallery_chrome.dart        EmptyGallery, GalleryStatusBar
      media_thumbnail_tile.dart  MediaThumbnailTile

  preview/
    image_preview_page.dart     ImagePreviewPage — full-screen preview shell
    preview_geometry.dart       Pure functions + constants (scale, navigation, timing)
    preview_models.dart         PreviewSource, PreviewAction, PreviewDisplayControl,
                                PreviewScaleDirection
    single_image_preview.dart   SingleImagePreview — zoomed single image
    widgets/
      preview_filmstrip.dart     PreviewFilmstrip, PreviewFilmstripThumbnail
      preview_hover_reveal.dart  PreviewHoverReveal
      preview_overview_map.dart  PreviewOverviewMap

  image_store.dart       ImageStore — decode cache keyed by path + layer + width
  justified_grid_layout.dart  Grid layout math
  lru_cache.dart         Generic LRU cache with sizeOf and onEvict
  media_filter.dart      MediaFilter enum and picker widget
  media_group.dart       MediaFile, MediaGroup, buildAdaptiveMediaGroups
  native_lib.dart        FFI bindings to libnative_lib / LibRaw
  viewer_image.dart      ViewerImage — ui.Image wrapper with clone/dispose
  worker_service.dart    WorkerService — isolate pool for RAW decoding

  l10n/
    app_en.arb           English strings (source of truth)
    app_zh.arb           Chinese strings
    app_localizations*.dart  Generated bindings — committed to the repo, not gitignored

test/
  core/
    preferences_repository_test.dart
  gallery/
    grid_zoom_accumulator_test.dart
    media_library_test.dart
  widget_test.dart       Integration/unit tests mirroring lib/ shape
  media_filter_test.dart
  media_group_test.dart

tool/                    Developer utilities (native decode checks)
android/, ios/, linux/, macos/, windows/
  Native integration code and vendored LibRaw source snapshots.
  android/app/src/main/cpp/libraw/ and windows/native_lib/libraw/
  Keep vendored trees aligned with their upstream.
```

## Architecture

**gallery/** and **preview/** are deliberately independent. Neither imports from
the other except at the single call site in `_HomePageState` where the preview
is opened. Keep them that way: a change to a gallery widget should never require
touching a preview file, and vice versa.

`core/` holds cross-cutting foundations with no dependency on gallery or preview.
`ui/` holds generic visual components (`AppTheme`, `DesktopControls`,
`RawImageWidget`, `FastPageScrollPhysics`) with no business logic.

New code belongs in the most specific layer it can live in. If it is used by
both gallery and preview it goes in `core/`. If it has no business semantics it
goes in `ui/`. State that belongs to a single widget stays private in that file.

## Development Workflow

```bash
flutter pub get
flutter analyze
flutter test
flutter test test/path/to/one_test.dart   # run a single test file
```

When changing platform or native code, build the affected target when the
toolchain is available:

```bash
flutter build android --release
flutter build linux  --release
flutter build macos  --release
flutter build windows --release
```

## Key Invariants

These are the easiest things to break silently:

**ViewerImage ownership** — every caller that receives a `ViewerImage` must call
`dispose()` when it is done. To share an image across two lifetimes, call
`clone()` and dispose each clone independently. The engine reference-counts the
underlying texture; the last clone to be disposed releases it.

**LruCache onEvict must dispose** — the `ImageStore` cache is created with
`onEvict: (_, image) => image.dispose()`. Any code that creates a new `LruCache`
for `ViewerImage` values must do the same, or eviction leaks GPU textures.

**All RAW decoding goes through WorkerService** — `WorkerService` runs a pool of
background isolates and handles cancellation, deduplication, and priority queuing.
Never call `getRawFastPreviewSync` or `getDecodedRawPreviewSync` on the main
isolate. Use `ImageStore.load` or `WorkerService.request*` instead.

**Decode width must go through `bucketDecodeWidth`** — this function rounds a
pixel width up to the nearest 128-pixel boundary. Decode widths also serve as
cache keys, so a raw `constraints.maxWidth` that changes pixel-by-pixel on every
window resize would invalidate every cached image. Always bucket the width before
passing it to `ImageStore` or `WorkerService`.

**All SharedPreferences keys live in `PreferencesRepository`** — the keys are
private constants there. Never add a `SharedPreferences.getInstance()` call
outside that class; a mistyped key silently drops the setting.

## Naming Conventions

Dart privacy is library-scoped: a `_` prefix makes a symbol private to its file.
Symbols that are used by more than one file must be public (no `_`). Symbols that
are only used within the file they are declared in should stay private. Do not use
`part` / `part of` — it preserves privacy without producing real module
boundaries and makes files harder to evolve independently.

## Localization

`lib/l10n/app_en.arb` and `lib/l10n/app_zh.arb` are the sources of truth.
The generated bindings (`app_localizations*.dart`) are **committed to the repo**
— there is no `l10n.yaml`; the default Flutter arb-dir and output-dir both point
to `lib/l10n/`. After editing either ARB file, run:

```bash
flutter gen-l10n
```

Then commit both the ARB changes and the regenerated Dart files together.
Always update both `app_en.arb` and `app_zh.arb` for every user-visible string.

## Change Guidelines

- Follow existing Dart and Flutter patterns before introducing new abstractions
  or dependencies.
- Prefer newer compatible versions when resolving dependency conflicts; keep
  toolchain and dependency versions current while preserving supported-platform
  compatibility.
- Keep UI responsive by leaving RAW decoding and other expensive work off the
  main isolate (see Key Invariants above).
- Do not edit generated build output or files covered by `.gitignore`.
- Avoid modifying vendored LibRaw files unless the task explicitly requires an
  upstream update or patch.
- Preserve behavior across Windows, macOS, Linux, Android, and iOS. Guard
  platform-specific code and validate the affected platform integration.
- Treat C and C++ native changes as cross-platform: update every corresponding
  platform implementation together unless a platform has no equivalent
  integration. Document and confirm any intentional exception.
- Add focused tests for behavior changes. Run `flutter analyze` and
  `flutter test` before committing.

## Completion and Collaboration

- A task is not complete until `flutter analyze` reports no issues and
  `flutter test` passes. For native or platform changes, also run the relevant
  platform build when the toolchain is available.
- When a requirement, tradeoff, or intended behavior needs confirmation, ask
  before choosing an implementation.
- When resolving multiple independent problems, keep their changes and git
  commits separate so each commit addresses one coherent problem.
