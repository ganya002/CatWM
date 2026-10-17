import AppKit
import Carbon
import Combine
import SwiftUI

extension ConfigDocument {
    @discardableResult
    func save() -> Bool {
        guard !unreadable else { return false }
        let text = serialize()
        do {
            try FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: Config.url, atomically: true, encoding: .utf8)
        } catch {
            if saveError == nil { saveError = error.localizedDescription }
            return false
        }
        savedText = text
        if saveError != nil { saveError = nil }
        WindowManager.shared.reload(showHUD: false)
        let errors = WindowManager.shared.config.errors
        if errors != fileErrors { fileErrors = errors }
        return true
    }

    func serialize(includeKeyboard: Bool = true, includeAnimation: Bool = true) -> String {
        func esc(_ s: String) -> String { s.replacingOccurrences(of: "#", with: "##") }
        var out = [
            "# Ouch config. Written by the Settings window; editing by hand is fine too.",
            "# SUPER = Command, ALT = Option, CTRL = Control.",
            "",
        ]
        if includeKeyboard { out += vars.map { "\($0.name) = \(esc($0.value))" } }
        out += [""] + Options.lines(config, includeAnimation: includeAnimation)
        out += [
            "",
            "# bind = MODS, key, dispatcher, args. Binds inside `submap = name` … `submap = reset` only work in",
            "# that mode (entered with the submap dispatcher); single keys are fine there, vim style.",
        ]
        func line(_ r: BindRow) -> String { "\(r.kind) = \(esc(r.mods)), \(esc(r.key)), \(r.dispatcher)" + (r.args.isEmpty ? "" : ", \(esc(r.args))") }
        guard includeKeyboard else {
            return (out + (extraLines.isEmpty ? [] : ["", "# Lines Ouch doesn't recognise, kept as-is"] + extraLines)).joined(separator: "\n") + "\n"
        }
        out += binds.filter { $0.submap.isEmpty }.map(line)
        for mode in submaps where !mode.isEmpty {
            out += ["", "submap = \(mode)"] + binds.filter { $0.submap == mode }.map(line) + ["submap = reset"]
        }
        if !extraLines.isEmpty {
            out += ["", "# Lines Ouch doesn't recognise, kept as-is"] + extraLines
        }
        return out.joined(separator: "\n") + "\n"
    }

    func resolvedMods(_ mods: String) -> String {
        var s = mods
        for v in vars.sorted(by: { $0.name.count > $1.name.count }) { s = s.replacingOccurrences(of: v.name, with: v.value) }
        return s
    }

    static func flags(_ mods: String) -> NSEvent.ModifierFlags? {
        var f: NSEvent.ModifierFlags = []
        for t in mods.uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch t {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": f.insert(.command)
            case "ALT", "OPT", "OPTION", "MOD1": f.insert(.option)
            case "CTRL", "CONTROL": f.insert(.control)
            case "SHIFT": f.insert(.shift)
            default: return nil
            }
        }
        return f
    }

    func modsString(for f: NSEvent.ModifierFlags) -> String {
        var rest = f
        var parts: [String] = []
        if let main = Self.flags(modValue), !main.isEmpty, f.isSuperset(of: main) {
            parts.append(modVarName)
            rest.subtract(main)
        }
        if rest.contains(.command) { parts.append("SUPER") }
        if rest.contains(.option) { parts.append("ALT") }
        if rest.contains(.control) { parts.append("CTRL") }
        if rest.contains(.shift) { parts.append("SHIFT") }
        return parts.joined(separator: " ")
    }

    func combos(_ row: BindRow) -> [Combo]? {
        guard let f = Self.flags(resolvedMods(row.mods)),
              case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return nil }
        var out: [Combo] = []
        for p in pairs {
            guard let code = keyCodes[p.key.lowercased()] else { return nil }
            out.append(Combo(code: code, flags: f.rawValue))
        }
        return out
    }

    func title(_ row: BindRow) -> String {
        Actions.match(row)?.title ?? Actions.rangeSummary(row)?.title ?? "\(row.dispatcher) \(row.args)"
    }

    func issue(_ row: BindRow) -> (severity: Severity, message: String)? {
        guard let f = Self.flags(resolvedMods(row.mods)) else { return (.error, "Unknown modifier in “\(row.mods)”") }
        if row.key.isEmpty { return (.error, "Click the shortcut and press the keys you want") }
        if case .failure(let e) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) {
            return (.error, e.message.prefix(1).uppercased() + e.message.dropFirst())
        }
        guard let mine = combos(row) else { return (.error, "Unknown key in “\(row.key)”") }
        if row.submap.isEmpty, f.subtracting(.shift).isEmpty, !mine.allSatisfy({ SpecialKey.isSwipe($0.code) }) {
            return (.error, "Add ⌥, ⌃ or ⌘, or put this in window mode, otherwise it would block normal typing")
        }
        let mineSet = Set(mine)
        if let other = binds.first(where: { o in
            o.id != row.id && o.submap == row.submap && !(combos(o).map { mineSet.isDisjoint(with: $0) } ?? true)
        }) {
            return (.error, "Overlaps “\(title(other))”")
        }
        if !Actions.dispatchers.contains(row.dispatcher) { return (.error, "Unknown action “\(row.dispatcher)”") }
        if row.dispatcher == "exec" && row.args.trimmingCharacters(in: .whitespaces).isEmpty {
            return (.error, "Enter the command to run")
        }
        if row.submap.isEmpty, f.contains(.option), f.isDisjoint(with: [.command, .control]) {
            let typed = mine.compactMap { c in Self.typedCharacter(keyCode: c.code, flags: f).map { (c, $0) } }
            if let first = typed.first {
                let key = Self.keyName(for: first.0.code) ?? ""
                let caps = prettyShortcut(BindRow(mods: row.mods, key: key, dispatcher: "", args: "")).joined()
                let more = typed.count > 1 ? " (and \(typed.count - 1) more)" : ""
                return (.warning, "\(caps) types “\(first.1)” on your keyboard layout\(more); this bind blocks it")
            }
        }
        if f == .command, !BindRange.isRange(row.key), Self.commonShortcuts.contains(row.key.lowercased()) {
            return (.warning, "Replaces a standard app shortcut (\(prettyShortcut(row).joined()))")
        }
        return nil
    }

}
