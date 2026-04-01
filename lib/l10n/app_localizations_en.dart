// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Raw Viewer';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get rawPreviewSourceSectionTitle => 'RAW Preview Source';

  @override
  String get fastPreviewTitle => 'Fast Preview';

  @override
  String get fastPreviewSubtitle =>
      'Show the cached fast preview first, then keep using the fast preview layer. This usually uses the embedded preview and falls back to fast RAW processing when unavailable.';

  @override
  String get decodedRawPreviewTitle => 'Decoded RAW';

  @override
  String get decodedRawPreviewSubtitle =>
      'Show the cached fast preview first, then decode RAW for the final image.';

  @override
  String get rawProcessingSectionTitle => 'RAW Processing';

  @override
  String get halfSizeRawDecodeTitle => 'Half-size RAW Decode';

  @override
  String get halfSizeRawDecodeSubtitle =>
      'Decode the final RAW image at 50% resolution for better speed. Disable for full resolution.';

  @override
  String get timeDisplaySectionTitle => 'Time Display';

  @override
  String get captureTimeTitle => 'Capture Time';

  @override
  String get captureTimeSubtitle => 'Prefer EXIF or RAW metadata capture time';

  @override
  String get fileModifiedTimeTitle => 'File Modified Time';

  @override
  String get fileModifiedTimeSubtitle =>
      'Use file system last modified time directly';

  @override
  String get cacheSectionTitle => 'Cache';

  @override
  String get maxCacheSizeTitle => 'Max Cache Size';

  @override
  String cacheSizeMb(int size) {
    return '$size MB';
  }

  @override
  String get windowsExplorerSectionTitle => 'Windows Explorer';

  @override
  String get windowsContextMenuMenuText => 'Open in RawView';

  @override
  String get windowsContextMenuToggleTitle => 'Show \"Open in RawView\"';

  @override
  String get windowsContextMenuEnabledSubtitle =>
      'Installed for the current user. Supports files, multiple files, folders, and right-click on folder background.';

  @override
  String get windowsContextMenuDisabledSubtitle =>
      'Enable this to open files, multiple files, folders, or the current directory directly from Explorer with \"Open in RawView\".';

  @override
  String get installScopeTitle => 'Install Scope';

  @override
  String get installScopeCurrentUser => 'Current user (HKCU)';

  @override
  String get installScopeNotInstalled => 'Not installed';

  @override
  String get windowsContextMenuEnabledMessage =>
      '\"Open in RawView\" context menu enabled';

  @override
  String get windowsContextMenuRemovedMessage =>
      '\"Open in RawView\" context menu removed';

  @override
  String windowsContextMenuUpdateFailed(String error) {
    return 'Failed to update Windows context menu: $error';
  }

  @override
  String get homeEmptyState => 'Open or drop RAW and image files/folders';

  @override
  String fileSelectionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String folderSelectionTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0';
  }

  @override
  String get fastPreviewShortLabel => 'FAST';

  @override
  String get rawShortLabel => 'RAW';

  @override
  String get imageShortLabel => 'IMG';
}
