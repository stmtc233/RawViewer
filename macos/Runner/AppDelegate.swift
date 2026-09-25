import Cocoa
import FlutterMacOS

final class ScopedFileAccess {
  static let shared = ScopedFileAccess()

  private var accessedPaths = Set<String>()
  private var accessedURLs: [URL] = []

  private init() {}

  /// Returns whether the process holds access to [url] afterwards.
  ///
  /// Access is started on [url] itself rather than a standardized copy: a URL
  /// resolved from a security-scoped bookmark carries its grant with it.
  @discardableResult
  func retainAccess(to url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    guard accessedPaths.insert(path).inserted else {
      return true
    }

    guard url.startAccessingSecurityScopedResource() else {
      accessedPaths.remove(path)
      return false
    }
    accessedURLs.append(url)
    return true
  }
}

final class OpenPathChannel {
  static let shared = OpenPathChannel()

  private let channelName = "rawviewer/open_paths"
  private var channel: FlutterMethodChannel?
  private var pendingPaths: [String] = []
  private var isReady = false

  private init() {}

  func attach(to flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }

      if call.method == "getInitialPaths" {
        self.isReady = true
        result(self.consumePendingPaths())
        return
      }

      result(FlutterMethodNotImplemented)
    }
  }

  func handle(paths: [String]) {
    let normalizedPaths = normalize(paths: paths)
    guard !normalizedPaths.isEmpty else {
      return
    }

    guard isReady, let channel else {
      pendingPaths.append(contentsOf: normalizedPaths)
      pendingPaths = normalize(paths: pendingPaths)
      return
    }

    channel.invokeMethod("openPaths", arguments: normalizedPaths)
  }

  private func consumePendingPaths() -> [String] {
    let paths = normalize(paths: pendingPaths)
    pendingPaths.removeAll()
    return paths
  }

  private func normalize(paths: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for openPath in paths {
      let normalizedPath = NSString(string: openPath).standardizingPath
      guard !normalizedPath.isEmpty else {
        continue
      }
      if seen.insert(normalizedPath).inserted {
        result.append(normalizedPath)
      }
    }

    return result
  }
}

final class DirectoryAccessChannel {
  static let shared = DirectoryAccessChannel()

  private let channelName = "rawviewer/macos_directory_access"
  private weak var flutterViewController: FlutterViewController?

  private init() {}

  func attach(to flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "selectDirectory":
        self.selectDirectory(arguments: call.arguments, result: result)
      case "createBookmark":
        result(self.createBookmark(arguments: call.arguments))
      case "restoreBookmark":
        result(self.restoreBookmark(arguments: call.arguments))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // A sandboxed app's access to a user-chosen path ends with the process. A
  // security-scoped bookmark is what lets a later launch reopen it.
  private func createBookmark(arguments: Any?) -> String? {
    guard let path = (arguments as? [String: Any])?["path"] as? String,
          !path.isEmpty
    else {
      return nil
    }

    let url = URL(fileURLWithPath: path)
    return try? url.bookmarkData(
      options: .withSecurityScope,
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ).base64EncodedString()
  }

  /// Resolves a bookmark from `createBookmark` and keeps access to it for the
  /// rest of the process. Returns the item's current path.
  private func restoreBookmark(arguments: Any?) -> String? {
    guard let bookmark = (arguments as? [String: Any])?["bookmark"] as? String,
          let data = Data(base64Encoded: bookmark)
    else {
      return nil
    }

    var isStale = false
    guard let url = try? URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    ), ScopedFileAccess.shared.retainAccess(to: url) else {
      return nil
    }
    return url.standardizedFileURL.path
  }

  private func selectDirectory(arguments: Any?, result: @escaping FlutterResult) {
    guard let window = flutterViewController?.view.window else {
      result(FlutterError(
        code: "window_unavailable",
        message: "Unable to present the directory access dialog.",
        details: nil
      ))
      return
    }

    let values = arguments as? [String: Any] ?? [:]
    let dialog = NSOpenPanel()
    dialog.canChooseFiles = false
    dialog.canChooseDirectories = true
    dialog.allowsMultipleSelection = false
    dialog.showsHiddenFiles = false

    if let initialDirectory = values["initialDirectory"] as? String,
       !initialDirectory.isEmpty {
      dialog.directoryURL = URL(fileURLWithPath: initialDirectory)
    }
    if let title = values["title"] as? String, !title.isEmpty {
      dialog.title = title
      dialog.message = title
      dialog.prompt = title
    }

    dialog.beginSheetModal(for: window) { response in
      guard response == .OK, let url = dialog.url else {
        result(nil)
        return
      }

      let selectedURL = url.standardizedFileURL
      ScopedFileAccess.shared.retainAccess(to: selectedURL)
      result(selectedURL.path)
    }
  }
}

final class FileAssociationChannel {
  static let shared = FileAssociationChannel()

  private let channelName = "rawviewer/file_associations"
  private let associations = FileAssociations(
    bundleIdentifier: Bundle.main.bundleIdentifier ?? ""
  )
  private var channel: FlutterMethodChannel?

  private init() {}

  func attach(to flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.channel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }

      switch call.method {
      case "getFileAssociationState":
        result(self.associations.state())
      case "setFileAssociations":
        guard let arguments = call.arguments as? [String: Any],
              let extensions = arguments["extensions"] as? [String]
        else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "Expected an extensions list.",
            details: nil
          ))
          return
        }

        if let error = self.associations.setAssociations(extensions: Set(extensions)) {
          result(FlutterError(
            code: "file_association_error",
            message: error,
            details: nil
          ))
        } else {
          result(self.associations.state())
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    ScopedFileAccess.shared.retainAccess(to: URL(fileURLWithPath: filename))
    OpenPathChannel.shared.handle(paths: [filename])
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    for filename in filenames {
      ScopedFileAccess.shared.retainAccess(to: URL(fileURLWithPath: filename))
    }
    OpenPathChannel.shared.handle(paths: filenames)
    sender.reply(toOpenOrPrint: .success)
  }
}
