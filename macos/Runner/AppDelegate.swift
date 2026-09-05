import Cocoa
import CoreServices
import FlutterMacOS

final class ScopedFileAccess {
  static let shared = ScopedFileAccess()

  private var accessedPaths = Set<String>()
  private var accessedURLs: [URL] = []

  private init() {}

  func retainAccess(to url: URL) {
    let normalizedURL = url.standardizedFileURL
    let path = normalizedURL.path
    guard accessedPaths.insert(path).inserted else {
      return
    }

    guard normalizedURL.startAccessingSecurityScopedResource() else {
      accessedPaths.remove(path)
      return
    }
    accessedURLs.append(normalizedURL)
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
      guard call.method == "selectDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }

      self.selectDirectory(arguments: call.arguments, result: result)
    }
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
  private let supportedExtensions = [
    "arw", "cr2", "cr3", "dng", "nef", "orf", "raf", "rw2", "srw",
    "jpg", "jpeg", "png", "webp",
  ]
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
        result(self.state())
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

        if let error = self.setAssociations(extensions: Set(extensions)) {
          result(FlutterError(
            code: "file_association_error",
            message: error,
            details: nil
          ))
        } else {
          result(self.state())
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func contentTypeIdentifier(for fileExtension: String) -> String {
    return "com.rawviewer.\(fileExtension)"
  }

  private func isAssociated(fileExtension: String) -> Bool {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      return false
    }
    let contentType = contentTypeIdentifier(for: fileExtension) as CFString
    guard let handler = LSCopyDefaultRoleHandlerForContentType(
      contentType,
      LSRolesMask.all
    )?.takeRetainedValue() as String?
    else {
      return false
    }
    return handler == bundleIdentifier
  }

  private func state() -> [String: Any] {
    var bindings: [String: Bool] = [:]
    for fileExtension in supportedExtensions {
      bindings[".\(fileExtension)"] = isAssociated(fileExtension: fileExtension)
    }
    return ["supported": true, "bindings": bindings]
  }

  private func setAssociations(extensions: Set<String>) -> String? {
    guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
      return "Unable to resolve the application bundle identifier."
    }

    for fileExtension in supportedExtensions {
      let extensionWithDot = ".\(fileExtension)"
      let shouldAssociate = extensions.contains(fileExtension) ||
        extensions.contains(extensionWithDot)
      let contentType = contentTypeIdentifier(for: fileExtension) as CFString
      let handler: CFString = shouldAssociate
        ? bundleIdentifier as CFString
        : "" as CFString
      let status = LSSetDefaultRoleHandlerForContentType(
        contentType,
        LSRolesMask.all,
        handler
      )
      if status != noErr {
        return "Failed to update the default application for .\(fileExtension) (\(status))."
      }
    }
    return nil
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
