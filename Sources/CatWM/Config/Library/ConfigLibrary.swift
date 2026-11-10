import AppKit
import CatWMKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ConfigLibrary: ObservableObject {
    static let builtInPrefix = "builtin."

    @Published var custom: [SavedConfig] = []
    @Published var builtIns: [SavedConfig] = []
    @Published var active: [ConfigKind: String] = [:]
    @Published var sheet: ConfigSheet?

    let doc: ConfigDocument
    let defaults = ConfigLibrary.makeBuiltIns()
    var observer: AnyCancellable?
    var applying = false

    static let url = Instance.configFolder.appendingPathComponent("configs.json")

    struct Stored: Codable { var custom: [SavedConfig]; var active: [String: String]; var edited: [SavedConfig]? }

    enum Clash { case keepBoth, rename, override, cancel }

    init(doc: ConfigDocument) {
        self.doc = doc
        builtIns = defaults
        load()
        observer = doc.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.reconcile() }
    }
}

extension UTType {
    static let catwmConfig = UTType(filenameExtension: "catwmconfig", conformingTo: .json) ?? .json
}
