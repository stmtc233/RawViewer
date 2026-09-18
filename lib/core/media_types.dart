import 'package:path/path.dart' as path;

/// File extensions the gallery offers, split by the pipeline that displays
/// them.
///
/// They are also the source of truth for the file picker and for the platform
/// file associations, so an entry added here has to be registered with every
/// platform integration as well:
///
/// * macOS — `macos/Runner/FileAssociations.swift` (extension to uniform type
///   identifier) and `macos/Runner/Info.plist` (document types). Launch
///   Services can only bind an extension it already resolves to a type, so a
///   format without a system type cannot be associated on macOS.
/// * Windows — `windows/runner/shell_integration.cpp`
///   (`kFileAssociationExtensions`, whose size is part of the declaration) and
///   the registry entries in `innosetup/rawviewer.iss`.
///
/// `tool/native_decode_check.dart` and the settings page read these lists
/// directly, so they need no separate update.
///
/// `rawExtensions` are containers LibRaw decodes. LibRaw identifies a file by
/// its contents rather than by its name, so this list only decides what is
/// offered; it is not a decoder table. Every entry is a format the bundled
/// LibRaw 0.22 build handles.
const List<String> rawExtensions = [
  '.3fr', // Hasselblad / Imacon
  '.arw', // Sony
  '.cr2', // Canon
  '.cr3', // Canon
  '.crw', // Canon CIFF (pre-CR2 bodies)
  '.dcr', // Kodak
  '.dng', // Adobe DNG, Apple ProRAW, DJI, Pentax and others
  '.erf', // Epson
  '.fff', // Hasselblad / Imacon
  '.iiq', // Phase One
  '.mos', // Leaf
  '.mrw', // Minolta / Konica Minolta
  '.nef', // Nikon
  '.nrw', // Nikon Coolpix
  '.orf', // Olympus / OM System
  '.pef', // Pentax / Ricoh
  '.raf', // Fujifilm
  '.raw', // Panasonic / Leica
  '.rw2', // Panasonic
  '.rwl', // Leica
  '.sr2', // Sony
  '.srf', // Sony
  '.srw', // Samsung
];

/// Extensions handed to Flutter's own image pipeline.
///
/// Only formats the engine decodes on every supported platform belong here.
/// TIFF and AVIF are decoded by the host operating system instead, so they work
/// on some platforms and not others; that is why they are absent.
const List<String> bitmapExtensions = [
  '.bmp',
  '.gif',
  '.heic',
  '.heif',
  '.jpeg',
  '.jpg',
  '.png',
  '.webp',
];

const List<String> supportedExtensions = [
  ...rawExtensions,
  ...bitmapExtensions,
];

String embeddedJpegExportFileName(String rawFilePath) {
  return '${path.basenameWithoutExtension(rawFilePath)}-embedded.jpg';
}
