import CoreServices
import Foundation
import UniformTypeIdentifiers

// Run from the repository root:
// swiftc macos/Runner/FileAssociations.swift tool/macos_file_association_check.swift -o /tmp/rawviewer-association-check
// /tmp/rawviewer-association-check
@main
struct FileAssociationCheck {
  static func main() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "macos/Runner/Info.plist"))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    let documentTypes = plist["CFBundleDocumentTypes"] as! [[String: Any]]
    let declared = Set(documentTypes.flatMap { $0["LSItemContentTypes"] as! [String] })
    for (ext, type) in FileAssociations.contentTypes {
      precondition(UTType(filenameExtension: ext)?.identifier == type, "Wrong system type for \(ext)")
      precondition(declared.contains(type), "Undeclared type: \(type)")
    }

    let suite = "rawviewer-association-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let app = "test.rawviewer"
    var handlers = Dictionary(uniqueKeysWithValues: Set(FileAssociations.contentTypes.values).map { ($0, "test.original") })
    var writes: [(String, String)] = []
    var failure: OSStatus = noErr
    var alternatives = ["test.other", "test.original", app]
    func makeAssociations() -> FileAssociations {
      FileAssociations(
        bundleIdentifier: app, defaults: defaults,
        currentHandler: { handlers[$0] },
        availableHandlers: { _ in alternatives },
        setHandler: { type, handler in
          precondition(!handler.isEmpty)
          if failure != noErr { return failure }
          writes.append((type, handler))
          handlers[type] = handler
          return noErr
        }
      )
    }
    var associations = makeAssociations()
    precondition(associations.setAssociations(extensions: [".jpg"]) == nil)
    precondition(writes.count == 1 && writes[0].0 == "public.jpeg")
    let state = associations.state()["bindings"] as! [String: Bool]
    precondition(state[".jpg"] == true && state[".jpeg"] == true)
    // Recreate the service to verify that restoring the previous app survives a restart.
    associations = makeAssociations()
    precondition(associations.setAssociations(extensions: [".jpeg"]) == nil)
    precondition(handlers["public.jpeg"] == "test.original")
    precondition(writes.count == 2)
    precondition(associations.setAssociations(extensions: []) == nil)
    precondition(writes.count == 2, "Unrelated associations must be preserved")

    failure = -50
    precondition(associations.setAssociations(extensions: [".png"]) != nil)
    precondition(handlers["public.png"] == "test.original")
    failure = noErr
    precondition(associations.setAssociations(extensions: [".png"]) == nil)
    alternatives = [app]
    precondition(associations.setAssociations(extensions: []) != nil)
    precondition(handlers["public.png"] == app)
    print("macOS association checks passed (system types, declarations, aliases, restoration, failures).")
  }
}
