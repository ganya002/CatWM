import AppKit
import SwiftUI

struct ShortcutIndex {
    private var mode: [String: [String]] = [:]
    private var global: [String: [String]] = [:]
    var modeName: String? = nil
    var modeChord: [String] = []

    init() {
        let text = (try? String(contentsOf: Config.url, encoding: .utf8)) ?? defaultText
        let doc = ConfigDocument(text: text)
        let modeBind = doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset" }
        if let modeBind {
            modeName = modeBind.args
            modeChord = doc.prettyShortcut(modeBind)
        }
        func table(_ submap: String) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for a in doc.keyActions(in: submap) where out[a.title] == nil {
                out[a.title] = ConfigDocument.modifierCaps(a.flags) + [ConfigDocument.capLabel(a.key)]
            }
            return out
        }
        if let m = modeName { mode = table(m) }
        global = table("")
    }

    func keys(_ dispatcher: String, _ args: String = "") -> [String] {
        guard let title = Actions.all.first(where: { $0.dispatcher == dispatcher && $0.args == args })?.title else { return [] }
        return mode[title] ?? global[title] ?? []
    }
}
