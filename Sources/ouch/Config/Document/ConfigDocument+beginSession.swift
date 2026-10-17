import AppKit
import Carbon
import Combine
import SwiftUI

extension ConfigDocument {
    func beginSession() {
        if !isDirty { load() }
        openedText = serialize()
    }

    func undoAllChanges() { apply(text: openedText) }
    func resetEverything() {
        let mod = modValue
        apply(text: defaultText)
        modValue = mod
    }

    static func replacingModToken(_ mods: String, with name: String) -> String {
        var out = "", tok = ""
        func flush() { out += tok == "$mod" ? name : tok; tok = "" }
        for ch in mods { if " _+".contains(ch) { flush(); out.append(ch) } else { tok.append(ch) } }
        flush()
        return out
    }

    func keyboardText() -> String {
        let all = serialize().components(separatedBy: "\n")
        let lines = vars.map { "\($0.name) = \($0.value.replacingOccurrences(of: "#", with: "##"))" } + [""]
            + all.filter { $0.hasPrefix("bind") || $0.hasPrefix("submap") || $0.isEmpty }
        return lines.joined(separator: "\n") + "\n"
    }

    func animationText() -> String {
        (Options.all.filter { $0.group == .animation }.map { "\($0.key) = \($0.text(config))" } + [""]).joined(separator: "\n")
    }

    func applyKeyboard(_ text: String) {
        let other = ConfigDocument(text: text)
        vars = other.vars
        binds = other.binds
    }

    func applyAnimation(_ text: String) {
        let c = Config.parse(text)
        for o in Options.all where o.group == .animation { o.copy(&config, c) }
    }

    func applyFull(_ text: String) { apply(text: text) }

    func backUpShortcuts() -> URL? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        let url = Config.url.deletingLastPathComponent().appendingPathComponent("keybinds-backup-\(f.string(from: Date())).conf")
        return (try? ("# Ouch keybind backup, \(Date())\n" + keyboardText()).write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    func load() {
        let text = try? String(contentsOf: Config.url, encoding: .utf8)
        let wasUnreadable = unreadable
        unreadable = text == nil && FileManager.default.fileExists(atPath: Config.url.path)
        apply(text: text ?? defaultText)
        fileErrors = config.errors
        savedText = serialize()
        if unreadable { saveError = "The config file can't be read, so it's left as it is" } else if wasUnreadable { saveError = nil }
    }

    func apply(text: String) {
        config = Config.parse(text)
        var newVars: [VarRow] = [], newBinds: [BindRow] = [], extra: [String] = []
        var resolved: [(String, String)] = []
        var submap = ""
        var blocks: [String] = []

        for raw in text.components(separatedBy: .newlines) {
            var line = stripComment(raw)
            line = line.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("{") { blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces)); continue }
            if line == "}" { _ = blocks.popLast(); continue }
            if line.isEmpty { continue }
            guard let eq = line.firstIndex(of: "=") else { extra.append(raw); continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let lower = key.lowercased()

            if lower == "submap" {
                submap = value.lowercased() == "reset" ? "" : value
                continue
            }
            if key.hasPrefix("$") {
                newVars.removeAll { $0.name == key }
                newVars.append(VarRow(name: key, value: value))
                resolved.append((key, value))
            } else if lower.hasPrefix("bind") {
                guard lower != "bindm" else { extra.append(raw); continue }
                let p = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if p.count >= 3 {
                    newBinds.append(BindRow(mods: p[0], key: p[1], dispatcher: p[2].lowercased(), args: p.count > 3 ? p[3] : "",
                                            submap: submap, kind: lower))
                } else {
                    extra.append(raw)
                }
            } else {
                var probe = Config()
                var v = value
                for (k, val) in resolved.sorted(by: { $0.0.count > $1.0.count }) { v = v.replacingOccurrences(of: k, with: val) }
                if probe.apply((blocks + [key]).joined(separator: ":"), v) != nil { extra.append(raw) }
            }
        }
        if !newVars.contains(where: { $0.name.lowercased().contains("mod") }) {
            newVars.insert(VarRow(name: "$mod", value: "ALT"), at: 0)
        }
        vars = newVars
        binds = newBinds
        extraLines = extra
    }

    func autosaveIfNeeded() {
        guard isDirty, problemCount == 0 else { return }
        save()
    }
}
