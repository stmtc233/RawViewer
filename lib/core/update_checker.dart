import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why an update check could not produce an answer.
///
/// Each case maps to one specific message on the About page. Surfacing a raw
/// exception string to the user says nothing actionable, so the transport
/// failures that actually happen are named here instead.
enum UpdateCheckFailure { network, rateLimited, unknown }

/// The outcome of one update check.
///
/// Exactly one of [latestVersion] (success) or [failure] is set.
class UpdateCheckResult {
  final String? latestVersion;
  final bool isUpdateAvailable;
  final UpdateCheckFailure? failure;
  final String? errorDetail;

  const UpdateCheckResult._({
    this.latestVersion,
    this.isUpdateAvailable = false,
    this.failure,
    this.errorDetail,
  });

  const UpdateCheckResult.upToDate(String version)
      : this._(latestVersion: version);

  const UpdateCheckResult.updateAvailable(String version)
      : this._(latestVersion: version, isUpdateAvailable: true);

  const UpdateCheckResult.failed(
    UpdateCheckFailure failure, {
    String? detail,
  }) : this._(failure: failure, errorDetail: detail);

  bool get succeeded => failure == null;
}

/// Fetches the latest release tag name, or throws.
///
/// Injected so tests exercise every branch without touching the network.
typedef LatestTagFetcher = Future<String> Function();

const String _latestReleaseUrl =
    'https://api.github.com/repos/stmtc233/rawviewer/releases/latest';

const Duration _requestTimeout = Duration(seconds: 10);

/// Thrown when GitHub answers with a status that is not a transport failure.
///
/// Public so a [LatestTagFetcher] test double can reproduce the rate-limit and
/// server-error branches without a socket.
class UpdateHttpStatusException implements Exception {
  final int statusCode;

  const UpdateHttpStatusException(this.statusCode);

  @override
  String toString() => 'UpdateHttpStatusException($statusCode)';
}

/// Reads `tag_name` from the GitHub releases API.
///
/// GitHub rejects requests without a User-Agent with 403, so one is always sent.
Future<String> fetchLatestTagFromGitHub() async {
  final client = HttpClient()..connectionTimeout = _requestTimeout;
  try {
    final request = await client
        .getUrl(Uri.parse(_latestReleaseUrl))
        .timeout(_requestTimeout);
    request.headers.set(HttpHeaders.userAgentHeader, 'RawViewer');
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final response = await request.close().timeout(_requestTimeout);
    if (response.statusCode != HttpStatus.ok) {
      // Drain so the socket can be reused or closed cleanly.
      await response.drain<void>();
      throw UpdateHttpStatusException(response.statusCode);
    }
    final body = await response
        .transform(utf8.decoder)
        .join()
        .timeout(_requestTimeout);
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['tag_name'] is! String) {
      throw const FormatException('Release payload has no tag_name');
    }
    return decoded['tag_name'] as String;
  } finally {
    client.close(force: true);
  }
}

/// Compares two dotted version strings, ignoring a leading `v` and any
/// `+build` / `-prerelease` suffix.
///
/// Returns a negative number when [a] is older than [b], zero when they name the
/// same release, and a positive number when [a] is newer. Missing components
/// count as zero, so `1.2` and `1.2.0` compare equal.
int compareSemver(String a, String b) {
  final left = _versionComponents(a);
  final right = _versionComponents(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var index = 0; index < length; index++) {
    final leftPart = index < left.length ? left[index] : 0;
    final rightPart = index < right.length ? right[index] : 0;
    if (leftPart != rightPart) {
      return leftPart < rightPart ? -1 : 1;
    }
  }
  return 0;
}

List<int> _versionComponents(String version) {
  var normalized = version.trim();
  if (normalized.startsWith('v') || normalized.startsWith('V')) {
    normalized = normalized.substring(1);
  }
  // Drop a build ("+42") or prerelease ("-beta.1") suffix; neither participates
  // in the "is there something newer" question this check answers.
  final cutoff = normalized.indexOf(RegExp(r'[+\-]'));
  if (cutoff >= 0) {
    normalized = normalized.substring(0, cutoff);
  }
  if (normalized.isEmpty) {
    throw FormatException('Not a version string: $version');
  }
  return normalized
      .split('.')
      .map((part) => int.parse(part.trim()))
      .toList(growable: false);
}

/// Asks GitHub whether a release newer than [currentVersion] exists.
///
/// Never throws: every failure becomes an [UpdateCheckResult] the UI can show.
Future<UpdateCheckResult> checkForUpdate({
  required String currentVersion,
  LatestTagFetcher fetchLatestTag = fetchLatestTagFromGitHub,
}) async {
  String tag;
  try {
    tag = await fetchLatestTag();
  } on UpdateHttpStatusException catch (error) {
    // 403 is how GitHub reports an exhausted unauthenticated rate limit; 429 is
    // the explicit form. Both mean "come back later", not "you are up to date".
    if (error.statusCode == HttpStatus.forbidden ||
        error.statusCode == HttpStatus.tooManyRequests) {
      return const UpdateCheckResult.failed(UpdateCheckFailure.rateLimited);
    }
    return UpdateCheckResult.failed(
      UpdateCheckFailure.unknown,
      detail: 'HTTP ${error.statusCode}',
    );
  } on SocketException {
    return const UpdateCheckResult.failed(UpdateCheckFailure.network);
  } on HttpException {
    return const UpdateCheckResult.failed(UpdateCheckFailure.network);
  } on TimeoutException {
    return const UpdateCheckResult.failed(UpdateCheckFailure.network);
  } catch (error) {
    return UpdateCheckResult.failed(
      UpdateCheckFailure.unknown,
      detail: '$error',
    );
  }

  try {
    final isNewer = compareSemver(tag, currentVersion) > 0;
    return isNewer
        ? UpdateCheckResult.updateAvailable(tag)
        : UpdateCheckResult.upToDate(tag);
  } on FormatException catch (error) {
    return UpdateCheckResult.failed(
      UpdateCheckFailure.unknown,
      detail: error.message,
    );
  }
}