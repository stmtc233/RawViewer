import CoreServices
import Foundation

final class FileAssociations {
  // JPG and JPEG are two extensions of the same Launch Services type.
  static let contentTypes = [
    "arw": "com.sony.arw-raw-image",
    "cr2": "com.canon.cr2-raw-image",
    "cr3": "com.canon.cr3-raw-image",
    "dng": "com.adobe.raw-image",
    "nef": "com.nikon.raw-image",
    "orf": "com.olympus.raw-image",
    "raf": "com.fuji.raw-image",
    "rw2": "com.panasonic.rw2-raw-image",
    "srw": "com.samsung.raw-image",
    "jpg": "public.jpeg",
    "jpeg": "public.jpeg",
    "png": "public.png",
    "webp": "org.webmproject.webp",
  ]

  private let bundleIdentifier: String
  private let defaults: UserDefaults
  private let currentHandler: (String) -> String?
  private let availableHandlers: (String) -> [String]
  private let setHandler: (String, String) -> OSStatus
  private let previousHandlersKey = "previousFileAssociationHandlers"

  init(
    bundleIdentifier: String,
    defaults: UserDefaults = .standard,
    currentHandler: @escaping (String) -> String? = { type in
      LSCopyDefaultRoleHandlerForContentType(type as CFString, .all)?
        .takeRetainedValue() as String?
    },
    availableHandlers: @escaping (String) -> [String] = { type in
      LSCopyAllRoleHandlersForContentType(type as CFString, .all)?
        .takeRetainedValue() as? [String] ?? []
    },
    setHandler: @escaping (String, String) -> OSStatus = { type, handler in
      LSSetDefaultRoleHandlerForContentType(type as CFString, .all, handler as CFString)
    }
  ) {
    self.bundleIdentifier = bundleIdentifier
    self.defaults = defaults
    self.currentHandler = currentHandler
    self.availableHandlers = availableHandlers
    self.setHandler = setHandler
  }

  func state() -> [String: Any] {
    var bindings: [String: Bool] = [:]
    for (fileExtension, contentType) in Self.contentTypes {
      bindings[".\(fileExtension)"] = currentHandler(contentType) == bundleIdentifier
    }
    return ["supported": !bundleIdentifier.isEmpty, "bindings": bindings]
  }

  func setAssociations(extensions: Set<String>) -> String? {
    guard !bundleIdentifier.isEmpty else {
      return "Unable to resolve the application bundle identifier."
    }
    let selected = Set(extensions.map {
      $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    })
    let groups = Dictionary(grouping: Self.contentTypes.keys, by: { Self.contentTypes[$0]! })
    var previousHandlers = defaults.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]

    for contentType in groups.keys.sorted() {
      let aliases = groups[contentType]!
      let current = currentHandler(contentType)
      let isBound = current == bundleIdentifier
      // A changed alias controls the shared type, in either direction.
      let shouldBind = isBound
        ? aliases.allSatisfy { selected.contains($0) }
        : aliases.contains { selected.contains($0) }
      if shouldBind == isBound { continue }

      let handler: String
      if shouldBind {
        handler = bundleIdentifier
        if let current { previousHandlers[contentType] = current }
      } else {
        let alternatives = availableHandlers(contentType).filter { $0 != bundleIdentifier }
        let previous = previousHandlers[contentType]
        guard let replacement = previous.flatMap({ alternatives.contains($0) ? $0 : nil })
          ?? alternatives.first else {
          return "No other application is available for \(aliases.sorted().joined(separator: ", "))."
        }
        handler = replacement
      }

      let status = setHandler(contentType, handler)
      if status != noErr {
        return "Failed to update the default application for \(aliases.sorted().joined(separator: ", ")) (\(status))."
      }
      if !shouldBind { previousHandlers.removeValue(forKey: contentType) }
      defaults.set(previousHandlers, forKey: previousHandlersKey)
    }
    return nil
  }
}
