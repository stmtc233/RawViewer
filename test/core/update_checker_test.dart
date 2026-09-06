import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/core/update_checker.dart';

void main() {
  group('compareSemver', () {
    test('orders releases by numeric component, not lexically', () {
      expect(compareSemver('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareSemver('1.9.0', '1.10.0'), lessThan(0));
      expect(compareSemver('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('ignores a leading v on either side', () {
      expect(compareSemver('v1.2.0', '1.2.0'), 0);
      expect(compareSemver('V1.3.0', 'v1.2.0'), greaterThan(0));
    });

    test('treats missing components as zero', () {
      expect(compareSemver('1.2', '1.2.0'), 0);
      expect(compareSemver('1.2.1', '1.2'), greaterThan(0));
    });

    test('ignores build and prerelease suffixes', () {
      expect(compareSemver('1.2.0+42', '1.2.0'), 0);
      expect(compareSemver('1.2.0-beta.1', '1.2.0'), 0);
      expect(compareSemver('1.3.0+1', '1.2.0+99'), greaterThan(0));
    });

    test('rejects a string with no version in it', () {
      expect(() => compareSemver('nightly', '1.0.0'), throwsFormatException);
    });
  });

  group('checkForUpdate', () {
    test('reports an update when the published tag is newer', () async {
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => 'v1.1.0',
      );

      expect(result.succeeded, isTrue);
      expect(result.isUpdateAvailable, isTrue);
      expect(result.latestVersion, 'v1.1.0');
    });

    test('reports up to date when the published tag matches', () async {
      final result = await checkForUpdate(
        currentVersion: '1.2.0',
        fetchLatestTag: () async => 'v1.2.0',
      );

      expect(result.succeeded, isTrue);
      expect(result.isUpdateAvailable, isFalse);
    });

    test('reports up to date when the local build is ahead of the release',
        () async {
      // A developer build carries a version no release has yet; that is not an
      // "update available".
      final result = await checkForUpdate(
        currentVersion: '2.0.0',
        fetchLatestTag: () async => 'v1.9.0',
      );

      expect(result.succeeded, isTrue);
      expect(result.isUpdateAvailable, isFalse);
    });

    test('maps a connection failure to the network case', () async {
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => throw const SocketException('offline'),
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, UpdateCheckFailure.network);
    });

    test('maps a 403 to the rate-limited case', () async {
      // GitHub reports an exhausted unauthenticated quota as 403, which must
      // not read as "you are up to date".
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => throw const UpdateHttpStatusException(403),
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, UpdateCheckFailure.rateLimited);
    });

    test('maps a server error to the unknown case with its status', () async {
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => throw const UpdateHttpStatusException(500),
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, UpdateCheckFailure.unknown);
      expect(result.errorDetail, contains('500'));
    });

    test('maps an unparsable tag to a failure rather than throwing', () async {
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => 'nightly-build',
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, UpdateCheckFailure.unknown);
    });

    test('never throws, whatever the fetcher does', () async {
      final result = await checkForUpdate(
        currentVersion: '1.0.0',
        fetchLatestTag: () async => throw StateError('boom'),
      );

      expect(result.succeeded, isFalse);
      expect(result.failure, UpdateCheckFailure.unknown);
    });
  });
}