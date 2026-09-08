# HDR and Live Photos

## Supported Files

- HEIC and HEIF images appear in the gallery, filmstrip, and preview.
- Apple Live Photos exported as a HEIC/HEIF/JPEG and a MOV with the same
  filename stem in the same directory expose a playback button in preview.
  Matching is case-insensitive. Keep both files together when exporting.
- Android JPEG Motion Photos using Google's MicroVideo offset or Motion Photo
  container-directory XMP are supported. The declared MP4 range is validated
  and copied to a temporary file when the active preview prepares playback.
- Proprietary motion formats without these XMP fields, embedded movies in
  HEIC containers, and Apple pairs with unrelated filenames are not detected.

Only the active photo prepares a paused player. Playback starts on demand,
initially muted. The sound button toggles audio before or during playback.
Completion and stopping rewind and retain the player for immediate reuse.
Navigation, backgrounding, and preview disposal release the player.
Temporary movies are removed after player disposal; original
photos and companion movies are never modified.

## HDR Output

HDR applies to information already present in the photo. RAW processing is
unchanged and remains SDR. Gallery thumbnails and overview images are SDR.

| Platform | HDR Still-Image Preview |
| --- | --- |
| macOS 14+ | Native NSImageView with high dynamic range on an EDR-capable screen |
| iOS 17+ | Native UIImageView with high dynamic range on an EDR-capable screen |
| Android 14+ | Native ImageView with gain maps or PQ/HLG data on an HDR display |
| Windows | SDR fallback; native HDR output is intentionally out of scope |
| Linux | SDR fallback; native HDR output is intentionally out of scope |

The system's image codec determines which HDR formats it can expand. Newer
ISO gain maps require newer Apple OS versions. HDR previews read the original
file, never the HEIC-to-PNG thumbnail conversion. Unsupported systems and
decode failures retain the normal bitmap preview. Native detail is bounded
to an 8192-pixel longest edge.

## Build and Runtime Dependencies

- Android now requires API 28 (Android 9). HDR still requires API 34 and a
  compatible display. The HEIC plugin uses the app's NDK version.
- iOS builds use Flutter's current minimum deployment target, iOS 15.
- Live playback uses AVFoundation on Apple platforms, the video_player Android
  backend, Windows Media Foundation, and media_kit/libmpv on Linux. Windows
  HEVC playback depends on an installed system HEVC decoder.
- Linux builds require `libheif-dev`, `libpng-dev`, `libmpv-dev`, and
  `libepoxy-dev`, in addition to the existing Flutter desktop dependencies.
  Deployments must provide the corresponding runtime libraries.
- Windows ARM64 HEIC builds require vcpkg packages
  `libheif[core]:arm64-windows` and `libpng:arm64-windows`, with
  `VCPKG_INSTALLATION_ROOT` or `VCPKG_ROOT` set. Release CI installs them and
  bundles their DLLs. This avoids linking the HEIC package's x64 binaries
  into ARM64 releases.

## Verification

Tests cover XMP bounds, malformed files, companion matching, extraction
ownership, stale discovery, playback actions, failures, and lifecycle cleanup.
Hardware HDR output still requires visual verification on a compatible
screen; an SDR screenshot cannot demonstrate extended luminance.
