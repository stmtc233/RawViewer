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
  String get gridAspectRatioSectionTitle => 'Grid Cell Ratio';

  @override
  String get gridAspectRatioAdaptive => 'Adaptive';

  @override
  String get navigationSectionTitle => 'Navigation';

  @override
  String get pageSwitchAnimationTitle => 'Page Switch Animation';

  @override
  String get pageSwitchAnimationSubtitle => 'Animate mouse-wheel page changes. Touch and trackpad swipes remain direct and follow the finger.';

  @override
  String get imagePreviewSectionTitle => 'Image Preview';

  @override
  String get previewToolbarOpacityTitle => 'Top Bar Opacity';

  @override
  String get previewFilmstripOpacityTitle => 'Navigation Bar Opacity';

  @override
  String get previewOverlayOpacityTitle => 'Tool and Overview Opacity';

  @override
  String get previewOverlayOpacitySubtitle => 'Set the resting opacity of preview controls. Hovered controls always become fully visible; 100% disables transparency.';

  @override
  String previewOverlayOpacityPercent(int percent) {
    return '$percent%';
  }

  @override
  String get languageSectionTitle => 'Language';

  @override
  String get languageSystem => 'Follow system';

  @override
  String get languageChineseSimplified => '简体中文';

  @override
  String get languageEnglish => 'English';

  @override
  String get rawProcessingSectionTitle => 'RAW Processing';

  @override
  String get halfSizeRawDecodeTitle => 'Half-size RAW Decode';

  @override
  String get halfSizeRawDecodeSubtitle => 'Decode the final RAW image at 50% resolution for better speed. Disable for full resolution.';

  @override
  String get timeDisplaySectionTitle => 'Time Display';

  @override
  String get captureTimeTitle => 'Capture Time';

  @override
  String get captureTimeSubtitle => 'Prefer EXIF or RAW metadata capture time';

  @override
  String get fileModifiedTimeTitle => 'File Modified Time';

  @override
  String get fileModifiedTimeSubtitle => 'Use file system last modified time directly';

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
  String get windowsContextMenuEnabledSubtitle => 'Installed for the current user. Supports files, multiple files, folders, and right-click on folder background.';

  @override
  String get windowsContextMenuDisabledSubtitle => 'Enable this to open files, multiple files, folders, or the current directory directly from Explorer with \"Open in RawView\".';

  @override
  String get installScopeTitle => 'Install Scope';

  @override
  String get installScopeCurrentUser => 'Current user (HKCU)';

  @override
  String get installScopeNotInstalled => 'Not installed';

  @override
  String get windowsContextMenuEnabledMessage => '\"Open in RawView\" context menu enabled';

  @override
  String get windowsContextMenuRemovedMessage => '\"Open in RawView\" context menu removed';

  @override
  String windowsContextMenuUpdateFailed(String error) {
    return 'Failed to update Windows context menu: $error';
  }

  @override
  String get fileAssociationsSectionTitle => 'Default file associations';

  @override
  String get openDefaultAppsSettings => 'Open default apps';

  @override
  String get refreshFileAssociations => 'Refresh file associations';

  @override
  String get fileAssociationDefault => 'Default: Raw Viewer';

  @override
  String get fileAssociationNotDefault => 'Raw Viewer is not the default';

  @override
  String fileAssociationFormatSubtitle(Object extension) {
    return 'Open .$extension files with Raw Viewer';
  }

  @override
  String get fileAssociationsEnableAll => 'Enable all';

  @override
  String get fileAssociationsEnableRaw => 'Enable RAW only';

  @override
  String get fileAssociationsDisableAll => 'Disable all';

  @override
  String fileAssociationsUpdateFailed(String error) {
    return 'Failed to update file associations: $error';
  }

  @override
  String get homeEmptyState => 'Open or drop RAW and image files/folders';

  @override
  String get openFolder => 'Open folder';

  @override
  String get openFiles => 'Open files';

  @override
  String get openInFinder => 'Open in Finder';

  @override
  String get openInExplorer => 'Open in Explorer';

  @override
  String get openInFileManager => 'Open in file manager';

  @override
  String get moreActionsTooltip => 'More actions';

  @override
  String get exportEmbeddedJpegMenuItem => 'Export embedded JPEG';

  @override
  String get exportEmbeddedJpegDialogTitle => 'Export embedded JPEG';

  @override
  String get embeddedJpegNotFoundMessage => 'This RAW file has no embedded JPEG';

  @override
  String get embeddedJpegExportedMessage => 'Embedded JPEG exported';

  @override
  String embeddedJpegExportFailedMessage(String error) {
    return 'Could not export the embedded JPEG: $error';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get closeSettingsTooltip => 'Close settings';

  @override
  String get rotateImageTooltip => 'Rotate image clockwise';

  @override
  String get rotateImageCounterclockwiseTooltip => 'Rotate image counterclockwise';

  @override
  String get zoomInImageTooltip => 'Zoom in';

  @override
  String get zoomOutImageTooltip => 'Zoom out';

  @override
  String get resetImageViewTooltip => 'Reset image view';

  @override
  String get previewDisplayControlsTooltip => 'Preview display';

  @override
  String get previewFilmstripTitle => 'Thumbnail navigation';

  @override
  String get previewOverviewTitle => 'Overview map';

  @override
  String get showPreviewFilmstripTooltip => 'Show thumbnail navigation';

  @override
  String get hidePreviewFilmstripTooltip => 'Hide thumbnail navigation';

  @override
  String get showPreviewOverviewTooltip => 'Show overview map';

  @override
  String get hidePreviewOverviewTooltip => 'Hide overview map';

  @override
  String get centerCurrentPreviewThumbnailTooltip => 'Center current thumbnail';

  @override
  String get loadDirectoryTooltip => 'Load images from this directory';

  @override
  String get loadDirectoryButtonLabel => 'Load directory';

  @override
  String get grantDirectoryAccessDialogTitle => 'Allow Raw Viewer to access this folder';

  @override
  String loadDirectoryFailedMessage(String error) {
    return 'Could not load the directory: $error';
  }

  @override
  String get largerThumbnailsTooltip => 'Larger thumbnails';

  @override
  String get smallerThumbnailsTooltip => 'Smaller thumbnails';

  @override
  String gridColumnsTooltip(int count) {
    return '$count columns';
  }

  @override
  String galleryItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

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
  String get mediaFilterTooltip => 'Filter image type';

  @override
  String mediaFilterAdaptive(int count) {
    return 'Adaptive ($count)';
  }

  @override
  String mediaFilterAll(int count) {
    return 'All ($count)';
  }

  @override
  String mediaFilterRaw(int count) {
    return 'RAW ($count)';
  }

  @override
  String mediaFilterImages(int count) {
    return 'Standard images ($count)';
  }

  @override
  String get mediaFilterEmptyState => 'No images match the current filter';

  @override
  String get rawViewModeTooltip => 'View mode';

  @override
  String get embeddedJpegModeLabel => 'Embedded JPG';

  @override
  String get decodedRawModeLabel => 'RAW';

  @override
  String get pairedJpegModeLabel => 'JPG';

  @override
  String get rawShortLabel => 'RAW';

  @override
  String get rawJpegShortLabel => 'R&J';

  @override
  String get imageShortLabel => 'IMG';
}
