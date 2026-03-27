import Cocoa
import FlutterMacOS

final class DragHandlingView: NSView {
  var onPathsDropped: (([String]) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.fileURL])
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  override var isOpaque: Bool {
    false
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    return nil
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    return droppedPaths(from: sender).isEmpty ? [] : .copy
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return droppedPaths(from: sender).isEmpty ? [] : .copy
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    return !droppedPaths(from: sender).isEmpty
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = droppedPaths(from: sender)
    guard !paths.isEmpty else {
      return false
    }

    onPathsDropped?(paths)
    return true
  }

  private func droppedPaths(from dragInfo: NSDraggingInfo) -> [String] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
    ]
    guard let urls = dragInfo.draggingPasteboard.readObjects(
      forClasses: [NSURL.self],
      options: options
    ) as? [URL] else {
      return []
    }

    return urls.map(\.path)
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    let contentBounds = self.contentView?.bounds ?? NSRect(origin: .zero, size: windowFrame.size)

    let dragHandlingView = DragHandlingView(frame: contentBounds)
    dragHandlingView.autoresizingMask = [.width, .height]
    dragHandlingView.onPathsDropped = { paths in
      OpenPathChannel.shared.handle(paths: paths)
    }

    self.contentView?.addSubview(dragHandlingView, positioned: .above, relativeTo: nil)

    RegisterGeneratedPlugins(registry: flutterViewController)
    OpenPathChannel.shared.attach(to: flutterViewController)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }
}
