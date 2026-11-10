import AppKit
import Carbon
import CatWMKit
import Combine
import SwiftUI

extension ConfigDocument {
    @discardableResult
    func save() -> Bool {
        guard !unreadable else { return false }
        let text = serialize()
        let store = ConfigStore.shared
        do {
            if store.isScript {
                try store.save(settings: ConfigText(text).config, from: settingsCopy ?? store.settingsCopy)
            } else {
                try FileManager.default.createDirectory(at: Config.url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try text.write(to: Config.url, atomically: true, encoding: .utf8)
            }
        } catch {
            if saveError == nil { saveError = error.localizedDescription }
            return false
        }
        savedText = text
        if saveError != nil { saveError = nil }
        WindowManager.shared.applyStoredConfig()
        let errors = WindowManager.shared.config.errors
        if errors != fileErrors { fileErrors = errors }
        let paths = store.overriddenPaths
        if paths != overrides { overrides = paths }
        return true
    }

    func serialize(includeKeyboard: Bool = true, includeAnimation: Bool = true) -> String {
        if includeKeyboard && includeAnimation {
            return source.editing(config: config, vars: vars, binds: binds)
        }
        var out = ["# CatWM config. Written by the Settings window; editing by hand is fine too."]
        if includeKeyboard { out.append(ConfigText.keyboard(vars: vars, binds: binds)) }
        out += Options.lines(config, includeAnimation: includeAnimation)
        out += extraLines
        return out.joined(separator: "\n") + "\n"
    }

    func resolvedMods(_ mods: String) -> String {
        var variables: [(name: String, value: String)] = []
        for variable in vars {
            var value = variable.value
            for previous in variables {
                value = value.replacingOccurrences(of: previous.name, with: previous.value)
            }
            variables.append((variable.name, value))
            variables.sort { $0.name.count > $1.name.count }
        }
        var resolved = mods
        for variable in variables {
            resolved = resolved.replacingOccurrences(of: variable.name, with: variable.value)
        }
        return resolved
    }

    func modsString(for flags: NSEvent.ModifierFlags) -> String {
        var rest = flags
        var parts: [String] = []
        if let main = ConfigText.flags(modValue), !main.isEmpty, flags.isSuperset(of: main) {
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
        guard case .success(let interpreted) = BindInterpretation.read(row, mods: resolvedMods(row.mods)) else {
            return nil
        }
        return combos(interpreted)
    }

    private func combos(_ interpreted: BindInterpretation) -> [Combo] {
        interpreted.bindings.map { Combo(code: $0.keyCode, flags: interpreted.flags.rawValue) }
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
        let interpreted: BindInterpretation
        switch BindInterpretation.read(row, mods: resolvedMods(row.mods)) {
        case .success(let value): interpreted = value
        case .failure(let failure):
            switch failure {
            case .modifier: return (.error, "Unknown modifier in “\(row.mods)”")
            case .range(let message):
                if row.key.isEmpty { return (.error, "Click the shortcut and press the keys you want") }
                return (.error, message.prefix(1).uppercased() + message.dropFirst())
            case .key:
                return (.error, row.key.isEmpty ? "Click the shortcut and press the keys you want"
                    : "Unknown key in “\(row.key)”")
            }
        }
        let flags = interpreted.flags
        let mine = combos(interpreted)
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
