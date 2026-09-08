import Foundation
import ImageIO
import CoreGraphics
#if os(macOS)
import Cocoa
import FlutterMacOS
#else
import UIKit
import Flutter
#endif

private let hdrDecodeQueue = DispatchQueue(label: "rawviewer.hdr.decode", qos: .userInitiated)

// One bounded decode at a time, with the original gain map still available to ImageIO.
@available(macOS 14.0, iOS 17.0, *)
private func decodeHDR(path: String, width: Int) -> CGImage? {
  guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)
  else { return nil }
  var isHDR = CGImageSourceCopyAuxiliaryDataInfoAtIndex(
    source, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
  if #available(macOS 15.0, iOS 18.0, *) {
    isHDR = isHDR || CGImageSourceCopyAuxiliaryDataInfoAtIndex(
      source, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil
  }
  // Inspect lazy image metadata before spending another decode on an SDR file.
  if !isHDR, let probe = CGImageSourceCreateImageAtIndex(
    source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) {
    if #available(macOS 15.0, iOS 18.0, *) { isHDR = probe.contentHeadroom > 1 }
    if let colorSpace = probe.colorSpace {
      isHDR = isHDR || CGColorSpaceUsesITUR_2100TF(colorSpace)
    }
  }
  guard isHDR else { return nil }
  let options: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: min(max(width, 128), 8192),
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceShouldAllowFloat: true,
    kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
  ]
  guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
  else { return nil }
  return image
}

final class HdrImagePlugin: NSObject {
  static func register(with registrar: FlutterPluginRegistrar) {
    #if os(macOS)
    let messenger = registrar.messenger
    #else
    let messenger = registrar.messenger()
    #endif
    let channel = FlutterMethodChannel(name: "rawviewer/hdr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "isSupported" else {
        result(FlutterMethodNotImplemented)
        return
      }
      #if os(macOS)
      if #available(macOS 14.0, *) {
        let screen = registrar.view?.window?.screen ?? NSScreen.main
        result((screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1)
      } else { result(false) }
      #else
      if #available(iOS 17.0, *) {
        let screen = registrar.viewController?.view.window?.screen ?? UIScreen.main
        result(screen.potentialEDRHeadroom > 1)
      } else { result(false) }
      #endif
    }
    registrar.register(HdrImageFactory(messenger: messenger), withId: "rawviewer/hdr_image")
  }
}

private final class HdrImageFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  #if os(macOS)
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    HdrNativeImageView(id: viewId, messenger: messenger)
  }
  #else
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    HdrNativeImageView(id: viewId, messenger: messenger)
  }
  #endif
}

#if os(macOS)
private final class HdrNativeImageView: NSImageView {
  private let channel: FlutterMethodChannel
  private var generation = 0

  init(id: Int64, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "rawviewer/hdr/\(id)", binaryMessenger: messenger)
    super.init(frame: .zero)
    imageScaling = .scaleProportionallyUpOrDown
    if #available(macOS 14.0, *) { preferredImageDynamicRange = .high }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "load",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            let width = arguments["width"] as? Int else {
        result(false)
        return
      }
      self.generation += 1
      let generation = self.generation
      hdrDecodeQueue.async { [weak self] in
        guard self != nil else { DispatchQueue.main.async { result(false) }; return }
        let image: CGImage?
        if #available(macOS 14.0, *) { image = decodeHDR(path: path, width: width) }
        else { image = nil }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation == generation, let image else {
            result(false)
            return
          }
          self.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
          result(true)
        }
      }
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  deinit { channel.setMethodCallHandler(nil) }
}
#else
private final class HdrNativeImageView: NSObject, FlutterPlatformView {
  private let imageView = UIImageView()
  private let channel: FlutterMethodChannel
  private var generation = 0

  init(id: Int64, messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "rawviewer/hdr/\(id)", binaryMessenger: messenger)
    super.init()
    imageView.contentMode = .scaleAspectFit
    imageView.isUserInteractionEnabled = false
    if #available(iOS 17.0, *) { imageView.preferredImageDynamicRange = .high }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "load",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            let width = arguments["width"] as? Int else {
        result(false)
        return
      }
      self.generation += 1
      let generation = self.generation
      hdrDecodeQueue.async { [weak self] in
        guard self != nil else { DispatchQueue.main.async { result(false) }; return }
        let image: CGImage?
        if #available(iOS 17.0, *) { image = decodeHDR(path: path, width: width) }
        else { image = nil }
        DispatchQueue.main.async { [weak self] in
          guard let self, self.generation == generation, let image else {
            result(false)
            return
          }
          self.imageView.image = UIImage(cgImage: image)
          result(true)
        }
      }
    }
  }

  func view() -> UIView { imageView }
  deinit { channel.setMethodCallHandler(nil) }
}
#endif
