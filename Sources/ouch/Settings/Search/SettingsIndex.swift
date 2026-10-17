import AppKit
import SwiftUI

enum SettingsIndex {
    static let all: [SettingEntry] = {
        let options = Options.all.compactMap(\.setting).map {
            SettingEntry(id: $0.id, title: $0.label, pane: $0.pane, advanced: $0.advanced, keywords: $0.keywords)
        }
        return Pane.allCases.flatMap { pane in (CustomSettingsIndex.all + options).filter { $0.pane == pane } }
    }()

    static func search(_ query: String, doc: ConfigDocument) -> [SettingEntry] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        func hit(_ text: String) -> Bool { let t = text.lowercased(); return words.allSatisfy { t.contains($0) } }
        let settings = all.filter { hit("\($0.title) \($0.keywords) \($0.pane.rawValue)") }
        let binds = doc.binds.filter { hit("\(doc.title($0)) \(doc.prettyShortcut($0).joined()) \($0.submap)") }
            .prefix(12)
            .map { SettingEntry(id: "bind.\($0.id)", title: doc.title($0), pane: .shortcuts, bind: $0) }
        return settings + binds
    }
}
