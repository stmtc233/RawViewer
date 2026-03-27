import Cocoa
import FlutterMacOS

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

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    OpenPathChannel.shared.handle(paths: [filename])
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    OpenPathChannel.shared.handle(paths: filenames)
    sender.reply(toOpenOrPrint: .success)
  }
}
