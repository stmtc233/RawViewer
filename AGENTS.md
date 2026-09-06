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
    raw_view_mode.dart         RawViewMode, resolveRawViewMode,
                               isRawViewModeAvailable

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
    preview_models.dart         PreviewAction, PreviewDisplayControl
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
    raw_view_mode_test.dart
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

## Image Model and Terminology

Several things are easy to confuse because the code, the native ABI, and the UI
strings all use overlapping words for them. This is the mapping.

### Layers — how an image is obtained (`RawLayer`, internal)

| Layer | native | What it is | Requested by |
| --- | --- | --- | --- |
| `RawLayer.thumbnail` | `get_thumbnail` | The cheapest image LibRaw can produce: embedded preview data when present, a half-size RAW decode otherwise. Content therefore varies per file. | Grid tiles, filmstrip, neighbour preload, the preview's first frame |
| `RawLayer.embeddedJpeg` | `get_embedded_jpeg` | The JPEG stored in the RAW container, passed through verbatim. **No fallback** — a null result means this file has none. | Preview (display + availability probe), export |
| `RawLayer.decoded` | `get_preview` | The final high-quality image, from `unpack()` + `dcraw_process()`. Always RGBA8888. | Preview |

`RawLayer.thumbnail` is only ever requested with a bounded `targetWidth`. The
full-screen layers (`embeddedJpeg`, `decoded`) are requested without one, at
their own resolution.

### View modes — what the user chose to look at (`RawViewMode`, user-facing)

| Mode | UI label (en / zh) | Source | Unavailable when |
| --- | --- | --- | --- |
| `embeddedJpeg` | Embedded JPG / 内嵌 JPG | `RawLayer.embeddedJpeg` | The RAW carries no embedded JPEG |
| `decodedRaw` | RAW / RAW | `RawLayer.decoded` | Never — always available for a RAW file |
| `pairedJpeg` | JPG / JPG | The sibling file on disk, via Flutter's image pipeline | The group has no paired JPEG |

There is no "fast" mode and no `FAST` label: that name described a layer whose
content varies per file, so it told the user nothing about what they were
looking at. The two things it conflated — the embedded JPEG and a cheap RAW
decode — are now separate.

### Two words that are not layers

**Thumbnail (缩略图) is also a size.** `RawLayer.thumbnail` is a layer, but "the
grid thumbnail" is that layer at a particular `targetWidth`. `targetWidth` is
part of `ImageStore.cacheKey`, so one file's grid-sized and filmstrip-sized
entries are two cache entries of one layer; downscaling happens once in
`decodeToUiImage`, never in native code.

`WorkerService` dedupes by `'$path:${type.name}:$halfSize'`, which does **not**
include the width. Two widgets wanting the same layer at different widths share
a single native decode and then produce two `ui.Image` cache entries from its
bytes.

For bitmap files there is no ImageStore involvement at all: a thumbnail is
`ResizeImage(FileImage(...), width: ...)` and Flutter's own image cache owns it.

**Paired JPEG is a display source, not a layer.**
`buildAdaptiveMediaGroups` matches a bitmap file to a RAW file by lowercased
stem (RAW+JPEG shooting). The bitmap becomes `MediaGroup.pairedJpeg`, is removed
from the grid as its own entry, and the RAW group is badged `R&J` instead of
`RAW`. It is a sibling file read from disk — unrelated to the RAW's embedded
JPEG, which lives inside the RAW container.

### Embedded JPEG is reached three ways

The same bytes, three call paths, and conflating them is the easiest mistake to
make here:

- **As its own view mode** — `RawLayer.embeddedJpeg`, no fallback. This is also
  the availability probe: the preview loads it on every RAW page and reports the
  result via `onEmbeddedJpegAvailability`, which is what greys out the mode.
- **As one possible input to the thumbnail layer** — `process_thumbnail()` tries
  `unpack_thumb()` first, but **falls back** to `half_size = 1` RAW processing
  when there is nothing usable. So a thumbnail-layer image is not necessarily
  the embedded JPEG.
- **As a file export** — `extractEmbeddedJpeg()` on a one-off `Isolate.run`,
  returning encoded bytes rather than a `ui.Image`. Not through `WorkerService`:
  a user-initiated export must not occupy a decode worker.

### Legacy native names

The native ABI names predate this vocabulary and are kept for compatibility:

- `get_thumbnail` returns the **thumbnail layer**, which may be a RAW decode
  rather than an embedded thumbnail.
- `get_preview` returns the **decoded RAW layer**, not "a preview".
- `ThumbnailResult.format` carries either encoded bytes or RGBA pixels, so the
  struct name says nothing about the payload. Read `RawPixelFormat`.

Do not rename these without changing every platform wrapper together
(`windows/`, `macos/`, `linux/`, `android/`).

## Loading Flows

### Gallery grid — `MediaThumbnailTile`

```
bitmap  → Image(ResizeImage(FileImage(path), width: resizeWidth))
          + a separate ImageStream used only to report the aspect ratio
            back to the justified grid layout

RAW     → imageStore.peek(thumbnail, targetWidth: resizeWidth)   // sync
          ↳ hit  : painted on the tile's very first frame
          ↳ miss : imageStore.load(thumbnail, targetWidth, TaskPriority.high)
```

`resizeWidth` is `bucketDecodeWidth(cellWidth * dpr)` clamped to 100–800 logical
px, computed in `_HomePageState.build`.

The task is **not cancelled** when a tile is recycled — see the invariant below.
Staleness is handled by comparing `_generation` instead.

### Full-screen preview, RAW — `SingleImagePreview`

```
initState  peek(thumbnail, thumbnailResizeWidth)         // grid-sized, soft
           ?? peek(thumbnail, previewThumbnailResizeWidth)
              → something on screen in the first frame; soft beats black

_loadRawDisplayLayers()
  1. load(embeddedJpeg), no targetWidth       → wanted in BOTH RAW modes:
     the image itself in embedded mode, the interim sharp image while a
     decode runs, and the availability probe either way.
     priority = low while isFastScrolling, otherwise high
  2. skip the decode when embedded mode already has its image
  3. otherwise load(decoded, halfSize: useHalfSizeRawDecode ? 1 : 0)
     tracked in _decodedRawTask so it can be cancelled
```

`_displayedImage` picks the one layer to paint, best first: in embedded mode the
embedded JPEG wins (falling through to the decode only when this file has none);
in decoded mode the decode wins once it lands. The cached thumbnail is the last
resort in both. `_buildRawPreview` paints exactly that one — stacking layers
would pay for a full-screen overdraw every frame. A small corner spinner means
"decoding in the background"; the centred spinner means nothing is available
yet.

Only the decoded-RAW task is cancellable (on page deactivation, on fast
scrolling, or when the mode switches away from `decodedRaw`).

### Full-screen preview, bitmap or paired JPEG — `_buildBitmapPreview`

Two stacked `Image` widgets, both `FileImage` + `ResizeImage`:

1. `thumbnailResizeWidth` — the entry the grid already warmed, so the page
   switch paints immediately.
2. `bucketDecodeWidth(viewportWidth * 2.0)` clamped to 4096 physical px, added
   only when the page is active and not fast-scrolling.

The cap exists because a full-resolution bitmap decode costs `w * h * 4` bytes
regardless of window size — an 8000×6000 JPEG is ~192 MB. The `2.0` factor is
zoom headroom.

### Filmstrip and preload

`PreviewFilmstripThumbnail`: RAW → `load(thumbnail, targetWidth: decodeWidth,
TaskPriority.low)`; bitmap → `ResizeImage(FileImage(...))`.

`ImagePreviewPage._preloadIndex` warms neighbours (±3, or ±1 while fast
scrolling) as soon as navigation *intent* is seen, not when the animation
reaches halfway:

- RAW → `load(thumbnail, targetWidth: filmstripWidth, low)`, then disposes the
  handle immediately. The point is populating the cache, not holding an image;
  the page that lands there peeks it synchronously.
- bitmap → `precacheImage` at `thumbnailResizeWidth`.

Preloading a *bounded* width matters: preloading full-resolution layers for six
neighbours would blow the cache budget on images nobody looks at.

### View mode selection and persistence

One app-wide mode, not per-file state. It is set **only** from the preview's
top-right switch — there is deliberately no settings-page equivalent, because
two controls for one value is what the old "RAW Preview Source" section got
wrong.

```
switch tapped
  → _ImagePreviewPageState._rawViewMode   (setState: this screen changes now)
  → onRawViewModeChanged → _updateSettings → PreferencesRepository
                                             (persists for the next launch)
```

Both halves are load-bearing. See the route-snapshot invariant below for why the
local copy cannot be dropped in favour of reading the settings.

`resolveRawViewMode()` narrows the preference to something this file can show;
`isRawViewModeAvailable()` decides which menu items are greyed out. Every mode
is always rendered in the menu — unavailable ones are disabled, never removed,
so the menu does not change shape between files. `decodedRaw` is the fallback
because it is the only mode available for every RAW file.

## Development Workflow

Choose validation by the behavior and dependencies affected, not by the number
of edited lines. These commands are a reference, not a checklist for every task:

```bash
dart format --output=none --set-exit-if-changed lib/path/to/changed.dart
dart analyze lib/path/to/changed.dart    # repeat for affected Dart files
flutter test test/path/to/relevant_test.dart
flutter analyze                        # full project, when required below
flutter test                           # full suite, when required below
```

Run `flutter pub get` only when dependencies changed or package resolution is
missing or stale. Format only changed Dart files; avoid unrelated formatting.
After ARB changes, run `flutter gen-l10n` as described under Localization.

### Validation Scope

| Change | Required validation |
| --- | --- |
| Documentation or comments only | Review the diff; no Flutter analysis, tests, or build. |
| Pure UI presentation: button position, spacing, colors, icons, or copy, with unchanged behavior | Check formatting and analyze changed Dart files. No automated tests or build by default. Regenerate localization bindings when applicable. |
| Local behavior: callbacks, state transitions, filtering, or a setting | Check formatting, analyze affected Dart files, and run the relevant test files. Add focused coverage for meaningful new behavior or a bug fix when existing tests do not cover it. |
| Shared behavior or high risk: caching, decoding, concurrency, image ownership, preference migrations, shared API changes, broad refactors, or dependency/toolchain changes | Check formatting, run full `flutter analyze` and `flutter test`, and add focused regression coverage where needed. |
| Native code or platform integration | Validate affected behavior and build the affected target when its toolchain is available. Also apply the shared/high-risk checks when changing FFI, decoding, shared contracts, or dependencies. |

The user manually checks visual changes and routine interactions. For pure
presentation changes, leave visual acceptance to that workflow; do not launch
automated screenshot runs or wait for manual confirmation to finish the edit.
Manual checking does not replace tests for hidden state, lifecycle, persistence,
or concurrency failures. A visual request that also changes callbacks, hit
testing, navigation, or state must use the behavior tier.

Start with the smallest checks that cover the affected behavior. Expand only
when the change's dependencies, a failure, or an unresolved risk warrants it.
Do not rerun a passing check unless subsequent edits affect what it verified.
A commit alone does not require a broader tier. Run full checks when the user
explicitly requests them or when preparing a release.

For an affected platform, choose the applicable build command:

```bash
flutter build apk --release
flutter build linux  --release
flutter build macos  --release
flutter build windows --release
flutter build ios --release --no-codesign
```

### Test Value and Maintenance

- Test observable behavior and failure cases: cache isolation and eviction,
  ownership, stale async results, persistence, parsing, and meaningful UI actions.
- Do not add tests solely for moving a button, changing a color, or tuning an
  animation. Avoid assertions that merely repeat implementation constants such
  as exact spacing, theme colors, or animation durations, unless the exact value
  is an explicit compatibility or product requirement. A duration assertion is
  not a performance test.
- Keep layout tests that protect usability, such as preventing overflow or
  keeping controls reachable. Prefer behavioral constraints over exact pixel
  positions or widget-tree structure.
- Extend the most relevant test file for the behavior. Do not create a new file
  for every small change or accumulate unrelated tests in `widget_test.dart`.
  File count is not a quality target; do not merge files merely to reduce it.
- When an intentional UI change breaks a brittle presentation assertion, revise
  or remove that assertion after checking its purpose. Preserve useful behavior
  coverage; never weaken tests just to make an unexplained failure pass. Leave
  unrelated test cleanup for a separate task.
- Read relevant tests and summarize results concisely. On failure, inspect the
  failing case and useful error context instead of repeatedly dumping full logs.

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
Never call `getRawThumbnailSync`, `getEmbeddedJpegImageSync`, or
`getDecodedRawPreviewSync` on the main isolate. Use `ImageStore.load` or
`WorkerService.request*` instead. (`extractEmbeddedJpeg()` is the one sanctioned
exception: it runs on its own `Isolate.run`, because a user-initiated export
returns encoded bytes and must not occupy a decode worker.)

**Decode width must go through `bucketDecodeWidth`** — this function rounds a
pixel width up to the nearest 128-pixel boundary. Decode widths also serve as
cache keys, so a raw `constraints.maxWidth` that changes pixel-by-pixel on every
window resize would invalidate every cached image. Always bucket the width before
passing it to `ImageStore` or `WorkerService`.

**Shared cheap layers must never be cancelled** — `WorkerService` dedupes by
path, so one widget cancelling its `RawLayer.thumbnail` or
`RawLayer.embeddedJpeg` task resolves every other widget's shared request to
`null`, leaving unrelated tiles showing a broken image. Grid tiles and the
preview both handle "no longer wanted" by ignoring a stale result (a
`_generation` counter), not by cancelling. Only the decoded-RAW task is
cancellable. See **Loading Flows**.

**All SharedPreferences keys live in `PreferencesRepository`** — the keys are
private constants there. Never add a `SharedPreferences.getInstance()` call
outside that class; a mistyped key silently drops the setting.

**A pushed route's settings are a snapshot** — `ImagePreviewPage` is opened with
`Navigator.push`, and a `PageRouteBuilder`'s `pageBuilder` runs once. Its
settings object is therefore frozen at open time; later changes on `HomePage`
never reach it. The field is named `initialSettings` to say so at every use site.

This is why the RAW view mode is *also* held in `_ImagePreviewPageState`: writing
it only through `onRawViewModeChanged` persists it correctly but leaves the
current screen unchanged until the preview is reopened. Anything the user can
change from **inside** the preview needs the same treatment — local state for
the visible effect, a callback for persistence. Making a setting genuinely live
across this boundary means lifting it into an `InheritedWidget` or a
`ValueListenable`, not reading `initialSettings` again.

The remaining reads of `initialSettings` (`pageSwitchAnimationEnabled`,
`previewOverlayOpacity`, `timeDisplaySource`) are correct today only because the
settings dialog is reachable from the gallery toolbar alone, so it cannot be
open at the same time as the preview. Adding a settings entry point to the
preview would break all three at once.

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
- Apply Validation Scope and Test Value and Maintenance above when deciding
  whether to add tests and which checks to run, including before committing.

## Completion and Collaboration

- A task is complete when the requested change is implemented and the checks
  required by Validation Scope pass. Full analysis, full tests, and platform
  builds are not universal completion requirements.
- In the final response, briefly state what changed and which checks ran. When
  skipping tests for a low-risk change, say so in one sentence. Report failed or
  unavailable required checks and their limitations; do not claim they passed.
- When a requirement, tradeoff, or intended behavior needs confirmation, ask
  before choosing an implementation.
- When resolving multiple independent problems, keep their changes and git
  commits separate so each commit addresses one coherent problem.
