import 'package:path/path.dart' as path;

const List<String> rawExtensions = [
  '.arw',
  '.cr2',
  '.cr3',
  '.dng',
  '.nef',
  '.orf',
  '.raf',
  '.rw2',
  '.srw',
];

const List<String> bitmapExtensions = [
  '.jpg',
  '.jpeg',
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
