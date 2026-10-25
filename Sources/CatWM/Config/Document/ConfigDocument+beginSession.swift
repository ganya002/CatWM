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
        var out = "", token = ""
        func flush() { out += token == "$mod" ? name : token; token = "" }
        for character in mods {
            if " _+".contains(character) { flush(); out.append(character) } else { token.append(character) }
        }
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
        (Options.all.filter { $0.group == .animation }.map { "\($0.key) = \($0.text(config))" } + [""])
            .joined(separator: "\n")
    }

    func applyKeyboard(_ text: String) {
        let other = ConfigDocument(text: text)
        vars = other.vars
        binds = other.binds
    }

    func applyAnimation(_ text: String) {
        let parsed = Config.parse(text)
        for option in Options.all where option.group == .animation { option.copy(&config, parsed) }
    }

    func applyFull(_ text: String) { apply(text: text) }

    func backUpShortcuts() -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let url = Config.url.deletingLastPathComponent()
            .appendingPathComponent("keybinds-backup-\(formatter.string(from: Date())).conf")
        let backup = "# CatWM keybind backup, \(Date())\n" + keyboardText()
        return (try? backup.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    func load() {
        let text = try? String(contentsOf: Config.url, encoding: .utf8)
        let wasUnreadable = unreadable
        unreadable = text == nil && FileManager.default.fileExists(atPath: Config.url.path)
        apply(text: text ?? defaultText)
        fileErrors = config.errors
        savedText = serialize()
        if unreadable {
            saveError = "The config file can't be read, so it's left as it is"
        } else if wasUnreadable {
            saveError = nil
        }
    }

    func apply(text: String) {
        config = Config.parse(text)
        var parse = ConfigTextParse()
        for raw in text.components(separatedBy: .newlines) { parse.read(raw) }
        if !parse.vars.contains(where: { $0.name.lowercased().contains("mod") }) {
            parse.vars.insert(VarRow(name: "$mod", value: "ALT"), at: 0)
        }
        vars = parse.vars
        binds = parse.binds
        extraLines = parse.extra
    }

    func autosaveIfNeeded() {
        guard isDirty, problemCount == 0 else { return }
        save()
    }
}

private struct ConfigTextParse {
    var vars: [VarRow] = []
    var binds: [BindRow] = []
    var extra: [String] = []
    private var resolved: [(String, String)] = []
    private var submap = ""
    private var blocks: [String] = []

    mutating func read(_ raw: String) {
        var line = stripComment(raw)
        line = line.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix("{") {
            blocks.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces))
            return
        }
        if line == "}" { _ = blocks.popLast(); return }
        if line.isEmpty { return }
        guard let equals = line.firstIndex(of: "=") else { extra.append(raw); return }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        let lower = key.lowercased()

        if lower == "submap" {
            submap = value.lowercased() == "reset" ? "" : value
            return
        }
        if key.hasPrefix("$") {
            vars.removeAll { $0.name == key }
            vars.append(VarRow(name: key, value: value))
            resolved.append((key, value))
        } else if lower.hasPrefix("bind") {
            readBind(raw, kind: lower, value: value)
        } else {
            readOption(raw, key: key, value: value)
        }
    }

    private mutating func readBind(_ raw: String, kind: String, value: String) {
        guard kind != "bindm" else { extra.append(raw); return }
        let parts = value.split(separator: ",", maxSplits: 3, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count >= 3 {
            binds.append(BindRow(mods: parts[0], key: parts[1], dispatcher: parts[2].lowercased(),
                                 args: parts.count > 3 ? parts[3] : "", submap: submap, kind: kind))
        } else {
            extra.append(raw)
        }
    }

    private mutating func readOption(_ raw: String, key: String, value: String) {
        var probe = Config()
        var expanded = value
        for (name, replacement) in resolved.sorted(by: { $0.0.count > $1.0.count }) {
            expanded = expanded.replacingOccurrences(of: name, with: replacement)
        }
        if probe.apply((blocks + [key]).joined(separator: ":"), expanded) != nil { extra.append(raw) }
    }
}
