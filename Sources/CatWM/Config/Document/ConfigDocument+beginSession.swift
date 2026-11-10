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
        ConfigText.keyboard(vars: vars, binds: binds)
    }

    func animationText() -> String {
        (Options.all.filter { $0.group == .animation }.map { "\($0.key) = \($0.text(config))" } + [""])
            .joined(separator: "\n")
    }

    func applyKeyboard(_ text: String) {
        let other = ConfigText(text)
        source = ConfigText(serialize()).materializingSettings()
        config = source.config
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
        let store = ConfigStore.shared
        if store.isScript {
            unreadable = false
            let copy = store.settingsCopy
            apply(text: copy.text)
            settingsCopy = copy
            fileErrors = store.current.errors
            overrides = store.overriddenPaths
            savedText = serialize()
            saveError = nil
            return
        }
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
        source = ConfigText(text)
        config = source.config
        vars = source.vars
        binds = source.binds
        extraLines = source.extraLines
    }

    func useScriptValue(_ path: String?) {
        do {
            try ConfigStore.shared.resetOverride(path)
        } catch {
            saveError = error.localizedDescription
            return
        }
        WindowManager.shared.applyStoredConfig()
        load()
    }

    func autosaveIfNeeded() {
        guard isDirty, problemCount == 0 else { return }
        save()
    }
}
