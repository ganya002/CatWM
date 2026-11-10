import AppKit
import CatWMKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension ConfigLibrary {
    static func makeBuiltIns() -> [SavedConfig] {
        func normalised(_ text: String) -> ConfigDocument { ConfigDocument(text: text) }
        let def = normalised(defaultText), wasd = normalised(wasdText)
        func make(_ id: String, _ kind: ConfigKind, _ name: String, _ text: String,
                  keyboard: String? = nil, animation: String? = nil) -> SavedConfig {
            SavedConfig(id: builtInPrefix + id, kind: kind, name: name, symbol: nil, colorHex: nil, text: text,
                        keyboardID: keyboard, animationID: animation)
        }
        return [
            make("keyboard.default", .keyboard, "Vim", def.keyboardText()),
            make("keyboard.wasd", .keyboard, "WASD", wasd.keyboardText()),
            make("animation.default", .animation, "Default", def.animationText()),
            make("full.default", .full, "Default", def.serialize(),
                 keyboard: builtInPrefix + "keyboard.default", animation: builtInPrefix + "animation.default")
        ]
    }

    func configs(_ kind: ConfigKind) -> [SavedConfig] {
        builtIns.filter { $0.kind == kind } + custom.filter { $0.kind == kind }
    }
    func config(id: String?) -> SavedConfig? {
        guard let id else { return nil }
        return builtIns.first { $0.id == id } ?? custom.first { $0.id == id }
    }
    func current(_ kind: ConfigKind) -> SavedConfig {
        config(id: active[kind]) ?? configs(kind)[0]
    }
    func isActive(_ config: SavedConfig) -> Bool { active[config.kind] == config.id }

    func load() {
        if let data = try? Data(contentsOf: Self.url), let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            custom = stored.custom
            for edit in stored.edited ?? [] {
                guard let i = builtIns.firstIndex(where: { $0.id == edit.id && $0.kind == edit.kind }) else { continue }
                builtIns[i] = edit
            }
            for (name, id) in stored.active { if let kind = ConfigKind(rawValue: name) { active[kind] = id } }
        } else {
            if FileManager.default.fileExists(atPath: Self.url.path) {
                let bak = Self.url.appendingPathExtension("bak")
                try? FileManager.default.removeItem(at: bak)
                Log.attempt("back up saved configs") { try FileManager.default.moveItem(at: Self.url, to: bak) }
            }
            adoptCurrentSettings()
        }
        for kind in ConfigKind.allCases where config(id: active[kind]) == nil { active[kind] = configs(kind)[0].id }
    }

    func save() {
        let stored = Stored(custom: custom,
                            active: Dictionary(uniqueKeysWithValues: active.map { ($0.key.rawValue, $0.value) }),
                            edited: builtIns.filter(isEdited))
        guard let data = try? JSONEncoder().encode(stored) else { return }
        Log.attempt("create configs folder") {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        }
        Log.attempt("save configs") { try data.write(to: Self.url, options: .atomic) }
    }

    func adoptCurrentSettings() {
        for kind in ConfigKind.allCases {
            let text = extract(kind)
            if let match = builtIns.first(where: { $0.kind == kind && $0.text == text }) {
                active[kind] = match.id
            } else {
                let mine = SavedConfig(id: UUID().uuidString, kind: kind, name: "My config", symbol: nil, colorHex: nil,
                                       text: text)
                custom.append(mine)
                active[kind] = mine.id
            }
        }
        refreshLinks()
        save()
    }

    func extract(_ kind: ConfigKind) -> String {
        switch kind {
        case .keyboard: doc.keyboardText()
        case .animation: doc.animationText()
        case .full: doc.serialize()
        }
    }

    func otherSettings(_ text: String) -> String {
        ConfigDocument(text: text).serialize(includeKeyboard: false, includeAnimation: false)
    }

    func refreshLinks() {
        guard let i = custom.firstIndex(where: { $0.id == active[.full] }) else { return }
        custom[i].keyboardID = active[.keyboard]
        custom[i].animationID = active[.animation]
    }

    func modify(_ id: String, _ change: (inout SavedConfig) -> Void) {
        if let i = builtIns.firstIndex(where: { $0.id == id }) {
            var config = builtIns[i]
            change(&config)
            if config != builtIns[i] { builtIns[i] = config }
        } else if let i = custom.firstIndex(where: { $0.id == id }) {
            var config = custom[i]
            change(&config)
            if config != custom[i] { custom[i] = config }
        }
    }

    func isEdited(_ config: SavedConfig) -> Bool {
        config.isBuiltIn && defaults.first { $0.id == config.id } != config
    }

    func reconcile() {
        guard !applying else { return }
        let before = (builtIns, custom)
        for kind in ConfigKind.allCases {
            let current = current(kind), text = extract(kind)
            if current.isBuiltIn, kind == .full, otherSettings(text) == otherSettings(current.text) { continue }
            modify(current.id) { $0.text = text }
        }
        refreshLinks()
        if before != (builtIns, custom) { save() }
    }

    func apply(_ config: SavedConfig) {
        applying = true
        switch config.kind {
        case .keyboard: doc.applyKeyboard(config.text)
        case .animation: doc.applyAnimation(config.text)
        case .full: doc.applyFull(config.text)
        }
        doc.save()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.applying = false }
    }
}
