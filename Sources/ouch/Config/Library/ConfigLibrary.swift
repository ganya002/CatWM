import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ConfigLibrary: ObservableObject {

    static let builtInPrefix = "builtin."
    static let reservedNames: [ConfigKind: [String]] = [.keyboard: ["Vim", "WASD"], .animation: ["Default"], .full: ["Default"]]

    @Published var custom: [SavedConfig] = []
    @Published var active: [ConfigKind: String] = [:]
    @Published var sheet: ConfigSheet?

    let doc: ConfigDocument
    var builtIns: [SavedConfig] = []
    var observer: AnyCancellable?
    var applying = false

    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/ouch/configs.json")

    struct Stored: Codable { var custom: [SavedConfig]; var active: [String: String] }

    static let editCopyName = "My config"

    enum Clash { case keepBoth, rename, override, cancel }

    init(doc: ConfigDocument) {
        self.doc = doc
        builtIns = Self.makeBuiltIns()
        load()
        observer = doc.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.reconcile() }
    }

}
