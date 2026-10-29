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
            try FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
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
        func esc(_ text: String) -> String { text.replacingOccurrences(of: "#", with: "##") }
        var out = [
            "# CatWM config. Written by the Settings window; editing by hand is fine too.",
            "# SUPER = Command, ALT = Option, CTRL = Control.",
            ""
        ]
        if includeKeyboard { out += vars.map { "\($0.name) = \(esc($0.value))" } }
        out += [""] + Options.lines(config, includeAnimation: includeAnimation)
        out += [
            "",
            "# bind = MODS, key, dispatcher, args. Binds inside `submap = name` … `submap = reset` only work in",
            "# that mode (entered with the submap dispatcher); single keys are fine there, vim style."
        ]
        func line(_ row: BindRow) -> String {
            "\(row.kind) = \(esc(row.mods)), \(esc(row.key)), \(row.dispatcher)"
                + (row.args.isEmpty ? "" : ", \(esc(row.args))")
        }
        guard includeKeyboard else {
            let kept = extraLines.isEmpty ? [] : ["", "# Lines CatWM doesn't recognise, kept as-is"] + extraLines
            return (out + kept).joined(separator: "\n") + "\n"
        }
        out += binds.filter(\.submap.isEmpty).map(line)
        for mode in submaps where !mode.isEmpty {
            out += ["", "submap = \(mode)"] + binds.filter { $0.submap == mode }.map(line) + ["submap = reset"]
        }
        if !extraLines.isEmpty {
            out += ["", "# Lines CatWM doesn't recognise, kept as-is"] + extraLines
        }
        return out.joined(separator: "\n") + "\n"
    }

    func resolvedMods(_ mods: String) -> String {
        var resolved = mods
        for variable in vars.sorted(by: { $0.name.count > $1.name.count }) {
            resolved = resolved.replacingOccurrences(of: variable.name, with: variable.value)
        }
        return resolved
    }

    static func flags(_ mods: String) -> NSEvent.ModifierFlags? {
        var flags: NSEvent.ModifierFlags = []
        for token in mods.uppercased().split(whereSeparator: { " _+".contains($0) }) {
            switch token {
            case "SUPER", "CMD", "COMMAND", "WIN", "META", "MOD4": flags.insert(.command)
            case "ALT", "OPT", "OPTION", "MOD1": flags.insert(.option)
            case "CTRL", "CONTROL": flags.insert(.control)
            case "SHIFT": flags.insert(.shift)
            default: return nil
            }
        }
        return flags
    }

    func modsString(for flags: NSEvent.ModifierFlags) -> String {
        var rest = flags
        var parts: [String] = []
        if let main = Self.flags(modValue), !main.isEmpty, flags.isSuperset(of: main) {
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
        guard let flags = Self.flags(resolvedMods(row.mods)),
              case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args)
        else { return nil }
        var out: [Combo] = []
        for pair in pairs {
            guard let code = keyCodes[pair.key.lowercased()] else { return nil }
            out.append(Combo(code: code, flags: flags.rawValue))
        }
        return out
    }

    func bindCombos() -> [UUID: [Combo]] {
        if let cache = comboCache, cache.binds == binds, cache.vars == vars { return cache.combos }
        var table: [UUID: [Combo]] = [:]
        for bind in binds { table[bind.id] = combos(bind) }
        comboCache = ComboCache(binds: binds, vars: vars, combos: table)
        return table
    }

    func title(_ row: BindRow) -> String {
        Actions.match(row)?.title ?? Actions.rangeSummary(row)?.title ?? "\(row.dispatcher) \(row.args)"
    }

    func issue(_ row: BindRow) -> (severity: Severity, message: String)? {
        guard let flags = Self.flags(resolvedMods(row.mods)) else {
            return (.error, "Unknown modifier in “\(row.mods)”")
        }
        if row.key.isEmpty { return (.error, "Click the shortcut and press the keys you want") }
        if case .failure(let failure) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) {
            return (.error, failure.message.prefix(1).uppercased() + failure.message.dropFirst())
        }
        guard let mine = combos(row) else { return (.error, "Unknown key in “\(row.key)”") }
        if row.submap.isEmpty, flags.subtracting(.shift).isEmpty, !mine.allSatisfy({ SpecialKey.isSwipe($0.code) }) {
            return (.error, "Add ⌥, ⌃ or ⌘, or put this in window mode, otherwise it would block normal typing")
        }
        let mineSet = Set(mine)
        let combosByBind = bindCombos()
        if let other = binds.first(where: { bind in
            bind.id != row.id && bind.submap == row.submap
                && !(combosByBind[bind.id].map { mineSet.isDisjoint(with: $0) } ?? true)
        }) {
            return (.error, "Overlaps “\(title(other))”")
        }
        if !Actions.dispatchers.contains(row.dispatcher) { return (.error, "Unknown action “\(row.dispatcher)”") }
        if row.dispatcher == "exec" && row.args.trimmingCharacters(in: .whitespaces).isEmpty {
            return (.error, "Enter the command to run")
        }
        if let typing = typingIssue(row, flags: flags, combos: mine) { return typing }
        if flags == .command, !BindRange.isRange(row.key), Self.commonShortcuts.contains(row.key.lowercased()) {
            return (.warning, "Replaces a standard app shortcut (\(prettyShortcut(row).joined()))")
        }
        return nil
    }

    private func typingIssue(_ row: BindRow, flags: NSEvent.ModifierFlags,
                             combos: [Combo]) -> (severity: Severity, message: String)? {
        guard row.submap.isEmpty, flags.contains(.option), flags.isDisjoint(with: [.command, .control]) else {
            return nil
        }
        let typed = combos.compactMap { combo in
            Self.typedCharacter(keyCode: combo.code, flags: flags).map { (combo, $0) }
        }
        guard let first = typed.first else { return nil }
        let key = Self.keyName(for: first.0.code) ?? ""
        let caps = prettyShortcut(BindRow(mods: row.mods, key: key, dispatcher: "", args: "")).joined()
        let more = typed.count > 1 ? " (and \(typed.count - 1) more)" : ""
        return (.warning, "\(caps) types “\(first.1)” on your keyboard layout\(more); this bind blocks it")
    }
}
