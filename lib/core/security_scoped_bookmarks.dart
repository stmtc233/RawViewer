import 'dart:io';

import 'package:flutter/services.dart';

import 'platform_channels.dart';

// A sandboxed macOS app keeps access to a user-chosen file or folder only for
// the process that received the grant; a stored path alone fails with
// "Operation not permitted" after a relaunch. A security-scoped bookmark is
// what carries the grant into a later launch.
//
// Both functions return null on other platforms and on any host failure, so
// callers can always fall back to the plain path.

/// Creates a bookmark for [path], which this process must currently be able
/// to access. The result is opaque and only meaningful to
/// [restoreSecurityScopedAccess].
Future<String?> createSecurityScopedBookmark(String path) =>
    _invoke('createBookmark', {'path': path});

/// Resolves [bookmark] and keeps access to it for the rest of the process.
/// Returns the item's current path, which differs from the recorded one when
/// the item has been moved or renamed.
Future<String?> restoreSecurityScopedAccess(String bookmark) =>
    _invoke('restoreBookmark', {'bookmark': bookmark});

Future<String?> _invoke(String method, Map<String, String> arguments) async {
  if (!Platform.isMacOS) {
    return null;
  }
  try {
    return await macOSDirectoryAccessChannel.invokeMethod<String>(
      method,
      arguments,
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}
