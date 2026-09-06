import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @exifRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get exifRating;

  /// No description provided for @exifRatingUnrated.
  ///
  /// In en, this message translates to:
  /// **'Unrated'**
  String get exifRatingUnrated;

  /// No description provided for @exifRatingMissing.
  ///
  /// In en, this message translates to:
  /// **'No rating data'**
  String get exifRatingMissing;

  /// No description provided for @exifRatingInvalid.
  ///
  /// In en, this message translates to:
  /// **'Unknown rating'**
  String get exifRatingInvalid;

  /// No description provided for @exifShutterShort.
  ///
  /// In en, this message translates to:
  /// **'Shutter'**
  String get exifShutterShort;

  /// No description provided for @exifApertureShort.
  ///
  /// In en, this message translates to:
  /// **'Aperture'**
  String get exifApertureShort;

  /// No description provided for @exifFocalLengthShort.
  ///
  /// In en, this message translates to:
  /// **'Focal length'**
  String get exifFocalLengthShort;

  /// No description provided for @exifExposureBiasShort.
  ///
  /// In en, this message translates to:
  /// **'Exposure comp.'**
  String get exifExposureBiasShort;

  /// No description provided for @exifEquivalentShort.
  ///
  /// In en, this message translates to:
  /// **'35 mm equiv.'**
  String get exifEquivalentShort;

  /// No description provided for @exifDimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get exifDimensions;

  /// No description provided for @exifTitle.
  ///
  /// In en, this message translates to:
  /// **'EXIF information'**
  String get exifTitle;

  /// No description provided for @showExifTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show EXIF information'**
  String get showExifTooltip;

  /// No description provided for @hideExifTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide EXIF information'**
  String get hideExifTooltip;

  /// No description provided for @exifCopyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all metadata'**
  String get exifCopyAll;

  /// No description provided for @exifSearch.
  ///
  /// In en, this message translates to:
  /// **'Search metadata'**
  String get exifSearch;

  /// No description provided for @exifClearSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get exifClearSearch;

  /// No description provided for @exifEmpty.
  ///
  /// In en, this message translates to:
  /// **'No readable EXIF metadata was found in this file.'**
  String get exifEmpty;

  /// No description provided for @exifReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read metadata from this file.'**
  String get exifReadFailed;

  /// No description provided for @exifNoResults.
  ///
  /// In en, this message translates to:
  /// **'No matching metadata'**
  String get exifNoResults;

  /// No description provided for @exifFileSection.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get exifFileSection;

  /// No description provided for @exifShootingSection.
  ///
  /// In en, this message translates to:
  /// **'Shooting details'**
  String get exifShootingSection;

  /// No description provided for @exifImageSection.
  ///
  /// In en, this message translates to:
  /// **'Image tags'**
  String get exifImageSection;

  /// No description provided for @exifExifSection.
  ///
  /// In en, this message translates to:
  /// **'EXIF tags'**
  String get exifExifSection;

  /// No description provided for @exifGpsSection.
  ///
  /// In en, this message translates to:
  /// **'GPS'**
  String get exifGpsSection;

  /// No description provided for @exifMakerSection.
  ///
  /// In en, this message translates to:
  /// **'Camera manufacturer tags'**
  String get exifMakerSection;

  /// No description provided for @exifThumbnailSection.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail tags'**
  String get exifThumbnailSection;

  /// No description provided for @exifOtherSection.
  ///
  /// In en, this message translates to:
  /// **'Other metadata'**
  String get exifOtherSection;

  /// No description provided for @exifFileName.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get exifFileName;

  /// No description provided for @exifFilePath.
  ///
  /// In en, this message translates to:
  /// **'Path'**
  String get exifFilePath;

  /// No description provided for @exifFileType.
  ///
  /// In en, this message translates to:
  /// **'File type'**
  String get exifFileType;

  /// No description provided for @exifFileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get exifFileSize;

  /// No description provided for @exifCameraMake.
  ///
  /// In en, this message translates to:
  /// **'Camera make'**
  String get exifCameraMake;

  /// No description provided for @exifCameraModel.
  ///
  /// In en, this message translates to:
  /// **'Camera model'**
  String get exifCameraModel;

  /// No description provided for @exifLensMake.
  ///
  /// In en, this message translates to:
  /// **'Lens make'**
  String get exifLensMake;

  /// No description provided for @exifLensModel.
  ///
  /// In en, this message translates to:
  /// **'Lens model'**
  String get exifLensModel;

  /// No description provided for @exifExposureTime.
  ///
  /// In en, this message translates to:
  /// **'Exposure time (s)'**
  String get exifExposureTime;

  /// No description provided for @exifAperture.
  ///
  /// In en, this message translates to:
  /// **'Aperture (f-number)'**
  String get exifAperture;

  /// No description provided for @exifIso.
  ///
  /// In en, this message translates to:
  /// **'ISO'**
  String get exifIso;

  /// No description provided for @exifFocalLength.
  ///
  /// In en, this message translates to:
  /// **'Focal length (mm)'**
  String get exifFocalLength;

  /// No description provided for @exifFocalLength35mm.
  ///
  /// In en, this message translates to:
  /// **'35 mm equivalent focal length (mm)'**
  String get exifFocalLength35mm;

  /// No description provided for @exifExposureBias.
  ///
  /// In en, this message translates to:
  /// **'Exposure compensation (EV)'**
  String get exifExposureBias;

  /// No description provided for @exifExposureProgram.
  ///
  /// In en, this message translates to:
  /// **'Exposure program'**
  String get exifExposureProgram;

  /// No description provided for @exifMeteringMode.
  ///
  /// In en, this message translates to:
  /// **'Metering mode'**
  String get exifMeteringMode;

  /// No description provided for @exifFlash.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get exifFlash;

  /// No description provided for @exifWhiteBalance.
  ///
  /// In en, this message translates to:
  /// **'White balance'**
  String get exifWhiteBalance;

  /// No description provided for @exifWidth.
  ///
  /// In en, this message translates to:
  /// **'Image width (px)'**
  String get exifWidth;

  /// No description provided for @exifHeight.
  ///
  /// In en, this message translates to:
  /// **'Image height (px)'**
  String get exifHeight;

  /// No description provided for @exifOrientation.
  ///
  /// In en, this message translates to:
  /// **'Orientation'**
  String get exifOrientation;

  /// No description provided for @exifColorSpace.
  ///
  /// In en, this message translates to:
  /// **'Color space'**
  String get exifColorSpace;

  /// No description provided for @exifSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get exifSoftware;

  /// No description provided for @exifArtist.
  ///
  /// In en, this message translates to:
  /// **'Artist'**
  String get exifArtist;

  /// No description provided for @exifCopyright.
  ///
  /// In en, this message translates to:
  /// **'Copyright'**
  String get exifCopyright;

  /// No description provided for @exifBodySerial.
  ///
  /// In en, this message translates to:
  /// **'Camera serial number'**
  String get exifBodySerial;

  /// No description provided for @exifLensSerial.
  ///
  /// In en, this message translates to:
  /// **'Lens serial number'**
  String get exifLensSerial;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Raw Viewer'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsCategoryGeneral;

  /// No description provided for @settingsCategoryAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsCategoryAppearance;

  /// No description provided for @settingsCategoryPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsCategoryPerformance;

  /// No description provided for @settingsCategoryIntegration.
  ///
  /// In en, this message translates to:
  /// **'System Integration'**
  String get settingsCategoryIntegration;

  /// No description provided for @settingsCategoryAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsCategoryAbout;

  /// No description provided for @gridAspectRatioSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Grid Cell Ratio'**
  String get gridAspectRatioSectionTitle;

  /// No description provided for @gridAspectRatioAdaptive.
  ///
  /// In en, this message translates to:
  /// **'Adaptive'**
  String get gridAspectRatioAdaptive;

  /// No description provided for @navigationSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigationSectionTitle;

  /// No description provided for @pageSwitchAnimationTitle.
  ///
  /// In en, this message translates to:
  /// **'Page Switch Animation'**
  String get pageSwitchAnimationTitle;

  /// No description provided for @pageSwitchAnimationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Animate mouse-wheel page changes. Touch and trackpad swipes remain direct and follow the finger.'**
  String get pageSwitchAnimationSubtitle;

  /// No description provided for @imagePreviewSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Image Preview'**
  String get imagePreviewSectionTitle;

  /// No description provided for @previewToolbarOpacityTitle.
  ///
  /// In en, this message translates to:
  /// **'Top Bar Opacity'**
  String get previewToolbarOpacityTitle;

  /// No description provided for @previewFilmstripOpacityTitle.
  ///
  /// In en, this message translates to:
  /// **'Navigation Bar Opacity'**
  String get previewFilmstripOpacityTitle;

  /// No description provided for @previewOverlayOpacityTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool and Overview Opacity'**
  String get previewOverlayOpacityTitle;

  /// No description provided for @previewOverlayOpacitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set the resting opacity of preview controls. Hovered controls always become fully visible; 100% disables transparency.'**
  String get previewOverlayOpacitySubtitle;

  /// No description provided for @previewOverlayOpacityPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String previewOverlayOpacityPercent(int percent);

  /// No description provided for @languageSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSectionTitle;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get languageSystem;

  /// No description provided for @languageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get languageChineseSimplified;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @rawProcessingSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'RAW Processing'**
  String get rawProcessingSectionTitle;

  /// No description provided for @halfSizeRawDecodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Half-size RAW Decode'**
  String get halfSizeRawDecodeTitle;

  /// No description provided for @halfSizeRawDecodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Decode the final RAW image at 50% resolution for better speed. Disable for full resolution.'**
  String get halfSizeRawDecodeSubtitle;

  /// No description provided for @timeDisplaySectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Time Display'**
  String get timeDisplaySectionTitle;

  /// No description provided for @captureTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Capture Time'**
  String get captureTimeTitle;

  /// No description provided for @captureTimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prefer EXIF or RAW metadata capture time'**
  String get captureTimeSubtitle;

  /// No description provided for @fileModifiedTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'File Modified Time'**
  String get fileModifiedTimeTitle;

  /// No description provided for @fileModifiedTimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use file system last modified time directly'**
  String get fileModifiedTimeSubtitle;

  /// No description provided for @cacheSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Cache'**
  String get cacheSectionTitle;

  /// No description provided for @maxCacheSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Max Cache Size'**
  String get maxCacheSizeTitle;

  /// No description provided for @cacheSizeMb.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String cacheSizeMb(int size);

  /// No description provided for @windowsExplorerSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Windows Explorer'**
  String get windowsExplorerSectionTitle;

  /// No description provided for @windowsContextMenuMenuText.
  ///
  /// In en, this message translates to:
  /// **'Open in RawView'**
  String get windowsContextMenuMenuText;

  /// No description provided for @windowsContextMenuToggleTitle.
  ///
  /// In en, this message translates to:
  /// **'Show \"Open in RawView\"'**
  String get windowsContextMenuToggleTitle;

  /// No description provided for @windowsContextMenuEnabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Installed for the current user. Supports files, multiple files, folders, and right-click on folder background.'**
  String get windowsContextMenuEnabledSubtitle;

  /// No description provided for @windowsContextMenuDisabledSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable this to open files, multiple files, folders, or the current directory directly from Explorer with \"Open in RawView\".'**
  String get windowsContextMenuDisabledSubtitle;

  /// No description provided for @installScopeTitle.
  ///
  /// In en, this message translates to:
  /// **'Install Scope'**
  String get installScopeTitle;

  /// No description provided for @installScopeCurrentUser.
  ///
  /// In en, this message translates to:
  /// **'Current user (HKCU)'**
  String get installScopeCurrentUser;

  /// No description provided for @installScopeNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get installScopeNotInstalled;

  /// No description provided for @windowsContextMenuEnabledMessage.
  ///
  /// In en, this message translates to:
  /// **'\"Open in RawView\" context menu enabled'**
  String get windowsContextMenuEnabledMessage;

  /// No description provided for @windowsContextMenuRemovedMessage.
  ///
  /// In en, this message translates to:
  /// **'\"Open in RawView\" context menu removed'**
  String get windowsContextMenuRemovedMessage;

  /// No description provided for @windowsContextMenuUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update Windows context menu: {error}'**
  String windowsContextMenuUpdateFailed(String error);

  /// No description provided for @fileAssociationsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Default file associations'**
  String get fileAssociationsSectionTitle;

  /// No description provided for @openDefaultAppsSettings.
  ///
  /// In en, this message translates to:
  /// **'Open default apps'**
  String get openDefaultAppsSettings;

  /// No description provided for @refreshFileAssociations.
  ///
  /// In en, this message translates to:
  /// **'Refresh file associations'**
  String get refreshFileAssociations;

  /// No description provided for @fileAssociationDefault.
  ///
  /// In en, this message translates to:
  /// **'Default: Raw Viewer'**
  String get fileAssociationDefault;

  /// No description provided for @fileAssociationNotDefault.
  ///
  /// In en, this message translates to:
  /// **'Raw Viewer is not the default'**
  String get fileAssociationNotDefault;

  /// No description provided for @fileAssociationFormatSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open .{extension} files with Raw Viewer'**
  String fileAssociationFormatSubtitle(Object extension);

  /// No description provided for @fileAssociationsEnableAll.
  ///
  /// In en, this message translates to:
  /// **'Enable all'**
  String get fileAssociationsEnableAll;

  /// No description provided for @fileAssociationsEnableRaw.
  ///
  /// In en, this message translates to:
  /// **'Enable RAW only'**
  String get fileAssociationsEnableRaw;

  /// No description provided for @fileAssociationsDisableAll.
  ///
  /// In en, this message translates to:
  /// **'Disable all'**
  String get fileAssociationsDisableAll;

  /// No description provided for @fileAssociationsUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update file associations: {error}'**
  String fileAssociationsUpdateFailed(String error);

  /// No description provided for @aboutAppDescription.
  ///
  /// In en, this message translates to:
  /// **'A fast RAW and standard image viewer powered by LibRaw.'**
  String get aboutAppDescription;

  /// No description provided for @aboutVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionTitle;

  /// No description provided for @aboutVersionValue.
  ///
  /// In en, this message translates to:
  /// **'{version} (build {build})'**
  String aboutVersionValue(String version, String build);

  /// No description provided for @aboutVersionLoading.
  ///
  /// In en, this message translates to:
  /// **'Reading version…'**
  String get aboutVersionLoading;

  /// No description provided for @aboutProjectHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Project home'**
  String get aboutProjectHomeTitle;

  /// No description provided for @aboutCopyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get aboutCopyTooltip;

  /// No description provided for @aboutCopiedMessage.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get aboutCopiedMessage;

  /// No description provided for @aboutLicenseTitle.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get aboutLicenseTitle;

  /// No description provided for @aboutLicenseValue.
  ///
  /// In en, this message translates to:
  /// **'MIT License · © 2026 stmtc233'**
  String get aboutLicenseValue;

  /// No description provided for @aboutCreditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCreditsTitle;

  /// No description provided for @aboutCreditsLibRaw.
  ///
  /// In en, this message translates to:
  /// **'RAW decoding by LibRaw (LGPL-2.1 / CDDL-1.0)'**
  String get aboutCreditsLibRaw;

  /// No description provided for @aboutUpdateSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get aboutUpdateSectionTitle;

  /// No description provided for @checkForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkForUpdates;

  /// No description provided for @checkingForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checkingForUpdates;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version {version} available'**
  String updateAvailable(String version);

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are on the latest version'**
  String get updateUpToDate;

  /// No description provided for @updateCheckFailedNetwork.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the update server. Check your connection.'**
  String get updateCheckFailedNetwork;

  /// No description provided for @updateCheckFailedRateLimited.
  ///
  /// In en, this message translates to:
  /// **'GitHub rate limit reached. Try again later.'**
  String get updateCheckFailedRateLimited;

  /// No description provided for @updateCheckFailedUnknown.
  ///
  /// In en, this message translates to:
  /// **'Could not check for updates: {error}'**
  String updateCheckFailedUnknown(String error);

  /// No description provided for @homeEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Open or drop RAW and image files/folders'**
  String get homeEmptyState;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get openFolder;

  /// No description provided for @openFiles.
  ///
  /// In en, this message translates to:
  /// **'Open files'**
  String get openFiles;

  /// No description provided for @recentOpenItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentOpenItemsTitle;

  /// No description provided for @noRecentOpenItems.
  ///
  /// In en, this message translates to:
  /// **'No recent files or folders'**
  String get noRecentOpenItems;

  /// No description provided for @openInFinder.
  ///
  /// In en, this message translates to:
  /// **'Open in Finder'**
  String get openInFinder;

  /// No description provided for @openInExplorer.
  ///
  /// In en, this message translates to:
  /// **'Open in Explorer'**
  String get openInExplorer;

  /// No description provided for @openInFileManager.
  ///
  /// In en, this message translates to:
  /// **'Open in file manager'**
  String get openInFileManager;

  /// No description provided for @moreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get moreActionsTooltip;

  /// No description provided for @exportEmbeddedJpegMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Export embedded JPEG'**
  String get exportEmbeddedJpegMenuItem;

  /// No description provided for @exportEmbeddedJpegDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export embedded JPEG'**
  String get exportEmbeddedJpegDialogTitle;

  /// No description provided for @embeddedJpegNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This RAW file has no embedded JPEG'**
  String get embeddedJpegNotFoundMessage;

  /// No description provided for @embeddedJpegExportedMessage.
  ///
  /// In en, this message translates to:
  /// **'Embedded JPEG exported'**
  String get embeddedJpegExportedMessage;

  /// No description provided for @embeddedJpegExportFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not export the embedded JPEG: {error}'**
  String embeddedJpegExportFailedMessage(String error);

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// No description provided for @closeSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get closeSettingsTooltip;

  /// No description provided for @rotateImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rotate image clockwise'**
  String get rotateImageTooltip;

  /// No description provided for @rotateImageCounterclockwiseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Rotate image counterclockwise'**
  String get rotateImageCounterclockwiseTooltip;

  /// No description provided for @zoomInImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomInImageTooltip;

  /// No description provided for @zoomOutImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOutImageTooltip;

  /// No description provided for @resetImageViewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reset image view'**
  String get resetImageViewTooltip;

  /// No description provided for @previewDisplayControlsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Preview display'**
  String get previewDisplayControlsTooltip;

  /// No description provided for @previewFilmstripTitle.
  ///
  /// In en, this message translates to:
  /// **'Thumbnail navigation'**
  String get previewFilmstripTitle;

  /// No description provided for @previewOverviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Overview map'**
  String get previewOverviewTitle;

  /// No description provided for @showPreviewFilmstripTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show thumbnail navigation'**
  String get showPreviewFilmstripTooltip;

  /// No description provided for @hidePreviewFilmstripTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide thumbnail navigation'**
  String get hidePreviewFilmstripTooltip;

  /// No description provided for @showPreviewOverviewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show overview map'**
  String get showPreviewOverviewTooltip;

  /// No description provided for @hidePreviewOverviewTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide overview map'**
  String get hidePreviewOverviewTooltip;

  /// No description provided for @centerCurrentPreviewThumbnailTooltip.
  ///
  /// In en, this message translates to:
  /// **'Center current thumbnail'**
  String get centerCurrentPreviewThumbnailTooltip;

  /// No description provided for @loadDirectoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'Load images from this directory'**
  String get loadDirectoryTooltip;

  /// No description provided for @loadDirectoryButtonLabel.
  ///
  /// In en, this message translates to:
  /// **'Load directory'**
  String get loadDirectoryButtonLabel;

  /// No description provided for @grantDirectoryAccessDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow Raw Viewer to access this folder'**
  String get grantDirectoryAccessDialogTitle;

  /// No description provided for @loadDirectoryFailedMessage.
  ///
  /// In en, this message translates to:
  /// **'Could not load the directory: {error}'**
  String loadDirectoryFailedMessage(String error);

  /// No description provided for @largerThumbnailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Larger thumbnails'**
  String get largerThumbnailsTooltip;

  /// No description provided for @smallerThumbnailsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Smaller thumbnails'**
  String get smallerThumbnailsTooltip;

  /// No description provided for @gridColumnsTooltip.
  ///
  /// In en, this message translates to:
  /// **'{count} columns'**
  String gridColumnsTooltip(int count);

  /// No description provided for @galleryItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String galleryItemCount(int count);

  /// No description provided for @fileSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String fileSelectionTitle(int count);

  /// No description provided for @folderSelectionTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}}'**
  String folderSelectionTitle(int count);

  /// No description provided for @mediaFilterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter image type'**
  String get mediaFilterTooltip;

  /// No description provided for @mediaFilterAdaptive.
  ///
  /// In en, this message translates to:
  /// **'Adaptive ({count})'**
  String mediaFilterAdaptive(int count);

  /// No description provided for @mediaFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String mediaFilterAll(int count);

  /// No description provided for @mediaFilterRaw.
  ///
  /// In en, this message translates to:
  /// **'RAW ({count})'**
  String mediaFilterRaw(int count);

  /// No description provided for @mediaFilterImages.
  ///
  /// In en, this message translates to:
  /// **'Standard images ({count})'**
  String mediaFilterImages(int count);

  /// No description provided for @mediaFilterEmptyState.
  ///
  /// In en, this message translates to:
  /// **'No images match the current filter'**
  String get mediaFilterEmptyState;

  /// No description provided for @rawViewModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get rawViewModeTooltip;

  /// No description provided for @embeddedJpegModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Embedded JPG'**
  String get embeddedJpegModeLabel;

  /// No description provided for @decodedRawModeLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW'**
  String get decodedRawModeLabel;

  /// No description provided for @pairedJpegModeLabel.
  ///
  /// In en, this message translates to:
  /// **'JPG'**
  String get pairedJpegModeLabel;

  /// No description provided for @rawShortLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW'**
  String get rawShortLabel;

  /// No description provided for @rawJpegShortLabel.
  ///
  /// In en, this message translates to:
  /// **'R&J'**
  String get rawJpegShortLabel;

  /// No description provided for @imageShortLabel.
  ///
  /// In en, this message translates to:
  /// **'IMG'**
  String get imageShortLabel;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
