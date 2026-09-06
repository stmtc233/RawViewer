import 'package:package_info_plus/package_info_plus.dart';

/// The app's own identity, read from the packaged build metadata.
///
/// `version` and `buildNumber` come from `pubspec.yaml` at build time, which CI
/// rewrites from the release tag. Reading them at runtime rather than hardcoding
/// a constant keeps the About page honest: there is no second place to forget to
/// update.
class AppInfo {
  final String version;
  final String buildNumber;

  const AppInfo({required this.version, required this.buildNumber});
}

/// Resolves [AppInfo]. Injected so tests do not reach for a platform channel.
typedef AppInfoLoader = Future<AppInfo> Function();

Future<AppInfo> loadAppInfoFromPlatform() async {
  final info = await PackageInfo.fromPlatform();
  return AppInfo(version: info.version, buildNumber: info.buildNumber);
}

/// The public repository this build is released from.
const String kProjectHomeUrl = 'https://github.com/stmtc233/rawviewer';