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
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
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

  /// No description provided for @rawPreviewSourceSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'RAW Preview Source'**
  String get rawPreviewSourceSectionTitle;

  /// No description provided for @fastPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Fast Preview'**
  String get fastPreviewTitle;

  /// No description provided for @fastPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show the cached fast preview first, then keep using the fast preview layer. This usually uses the embedded preview and falls back to fast RAW processing when unavailable.'**
  String get fastPreviewSubtitle;

  /// No description provided for @decodedRawPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Decoded RAW'**
  String get decodedRawPreviewTitle;

  /// No description provided for @decodedRawPreviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Show the cached fast preview first, then decode RAW for the final image.'**
  String get decodedRawPreviewSubtitle;

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

  /// No description provided for @homeEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Open or drop RAW and image files/folders'**
  String get homeEmptyState;

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

  /// No description provided for @fastPreviewShortLabel.
  ///
  /// In en, this message translates to:
  /// **'FAST'**
  String get fastPreviewShortLabel;

  /// No description provided for @rawShortLabel.
  ///
  /// In en, this message translates to:
  /// **'RAW'**
  String get rawShortLabel;

  /// No description provided for @imageShortLabel.
  ///
  /// In en, this message translates to:
  /// **'IMG'**
  String get imageShortLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
