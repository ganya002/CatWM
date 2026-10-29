import AppKit
import Carbon
import Combine
import SwiftUI
import UniformTypeIdentifiers

final class ConfigDocument: ObservableObject {
    @Published var config = Config()
    @Published var vars: [VarRow] = []
    @Published var binds: [BindRow] = []
    @Published var fileErrors: [String] = []
    @Published var saveError: String?
    var savedText = ""
    var openedText = ""
    var extraLines: [String] = []
    var unreadable = false
    var autosave: AnyCancellable?
    var comboCache: ComboCache?

    static let modifierChoices: [(value: String, label: String)] = [
        ("ALT", "⌥ Option"), ("SUPER", "⌘ Command"), ("CTRL", "⌃ Control"),
        ("ALT CTRL", "⌃⌥ Control + Option"), ("CTRL SHIFT", "⌃⇧ Control + Shift"), ("SUPER ALT", "⌥⌘ Option + Command"),
        ("SUPER CTRL", "⌃⌘ Control + Command")
    ]

    var extraLineCount: Int { extraLines.count }
    var isDirty: Bool { serialize() != savedText }
    var hasChangesSinceOpen: Bool { serialize() != openedText }

    var modVarName: String { vars.first { $0.name.lowercased().contains("mod") }?.name ?? "$mod" }

    var modValue: String {
        get { vars.first { $0.name == modVarName }?.value ?? "ALT" }
        set {
            if let i = vars.firstIndex(where: { $0.name == modVarName }) {
                vars[i].value = newValue
            } else {
                vars.insert(VarRow(name: modVarName, value: newValue), at: 0)
            }
        }
    }

    enum Severity { case error, warning }

    static let commonShortcuts: Set<String> = [
        "q", "w", "c", "v", "x", "z", "a", "s", "t", "n", "h", "m", "f", "p", "o", "r", "tab", "space", "comma"
    ]

    struct Combo: Hashable { let code: UInt16; let flags: UInt }

    struct ComboCache {
        let binds: [BindRow]
        let vars: [VarRow]
        let combos: [UUID: [Combo]]
    }

    var submaps: [String] {
        var seen = [""]
        for bind in binds where !seen.contains(bind.submap) { seen.append(bind.submap) }
        for bind in binds where bind.dispatcher == "submap" && bind.args.lowercased() != "reset"
            && !seen.contains(bind.args) {
            seen.append(bind.args)
        }
        return seen
    }

    var problemCount: Int { binds.filter { issue($0)?.severity == .error }.count }

    static let canonicalKeyNames: [UInt16: String] = [
        10: "section", 93: "yen", 94: "underscore_jis", 102: "eisu", 104: "kana"
    ]

    static let keySymbols = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "return": "↩", "enter": "↩", "tab": "⇥",
        "space": "Space", "escape": "⎋", "esc": "⎋", "capslock": "⇪", "caps": "⇪", "caps_lock": "⇪", "backspace": "⌫",
        "delete": "⌦", "comma": ",", "period": ".", "minus": "−", "equal": "=", "bracketleft": "[", "bracketright": "]",
        "semicolon": ";", "apostrophe": "'", "quote": "'", "slash": "/", "backslash": "\\", "grave": "`",
        "pageup": "⇞", "pagedown": "⇟", "home": "↖", "end": "↘",
        "mouse_up": "Scroll ↑", "mouse_down": "Scroll ↓", "mouse_left": "Scroll ←", "mouse_right": "Scroll →",
        "section": "§", "yen": "¥", "underscore_jis": "_", "eisu": "英数", "kana": "かな",
        "swipe_left": "Swipe ←", "swipe_right": "Swipe →", "swipe_up": "Swipe ↑", "swipe_down": "Swipe ↓"
    ]

    struct KeyAction: Identifiable {
        let code: UInt16
        let key: String
        let flags: NSEvent.ModifierFlags
        let arg: String
        let title: String
        let symbol: String
        let category: ActionCategory
        let row: BindRow
        var isRange: Bool { BindRange.isRange(row.key) }
        var id: String { "\(row.id) \(code)" }
    }

    init(text: String) { apply(text: text) }

    init() {
        load()
        autosave = objectWillChange
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] in self?.autosaveIfNeeded() }
    }
}

struct VarRow: Equatable {
    var name: String
    var value: String
}

struct BindRow: Identifiable, Equatable {
    let id = UUID()
    var mods: String
    var key: String
    var dispatcher: String
    var args: String
    var submap = ""
    var kind = "bind"
}

extension ConfigDocument {
    var skippedLineCount: Int { extraLineCount }
}
