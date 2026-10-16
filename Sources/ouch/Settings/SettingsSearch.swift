// Settings: the search index of every setting and the anchors that scroll to one.
import AppKit
import SwiftUI

// MARK: - Search index

/// One setting the search can find, hidden ones included.
struct SettingEntry: Identifiable {
    let id: String
    let title: String
    let pane: Pane
    var advanced = false
    var keywords = ""
    /// For shortcut results: the row to reveal.
    var bind: BindRow? = nil
}

enum SettingsIndex {
    /// Every row, pane by pane: the rows below, then the config options' rows from `Options`.
    static let all: [SettingEntry] = {
        let options = Options.all.compactMap(\.setting).map {
            SettingEntry(id: $0.id, title: $0.label, pane: $0.pane, advanced: $0.advanced, keywords: $0.keywords)
        }
        return Pane.allCases.flatMap { pane in (rows + options).filter { $0.pane == pane } }
    }()

    /// Rows that are not one config option: permissions, login, updates, reset, and rows that set several options.
    private static let rows: [SettingEntry] = [
        SettingEntry(id: "general.status", title: "Accessibility access", pane: .general, keywords: "permission status running grant"),
        SettingEntry(id: "general.login", title: "Open at login", pane: .general, keywords: "startup launch login items"),
        SettingEntry(id: "general.inputMonitoring", title: "Instant Caps Lock shortcuts", pane: .general, keywords: "input monitoring permission"),
        SettingEntry(id: "general.tiling", title: "Tiling", pane: .general, keywords: "enable disable pause on off"),
        SettingEntry(id: "general.modifier", title: "Shortcut key", pane: .general, keywords: "main modifier mod key option command control super"),
        SettingEntry(id: "general.autoCheck", title: "Check for updates automatically", pane: .general, keywords: "update sparkle"),
        SettingEntry(id: "general.autoDownload", title: "Download updates automatically", pane: .general, keywords: "update sparkle"),
        SettingEntry(id: "general.checkNow", title: "Check for updates", pane: .general, keywords: "update version"),
        SettingEntry(id: "general.beta", title: "Include beta releases", pane: .general, keywords: "update channel early"),
        SettingEntry(id: "general.reset", title: "Reset all settings", pane: .general, keywords: "defaults restore factory"),

        SettingEntry(id: "layout.displays", title: "Layout per display", pane: .layout, keywords: "screen monitor current"),
        SettingEntry(id: "layout.cycle", title: "Active layouts", pane: .layout, keywords: "order next previous tall wide bsp column"),
        SettingEntry(id: "layout.padding", title: "Screen padding", pane: .layout, keywords: "edges margin inset"),
        SettingEntry(id: "layout.linked", title: "Same padding on every side", pane: .layout, advanced: true, keywords: "top bottom left right"),

        SettingEntry(id: "windows.sortCrowded", title: "Crowded from", pane: .windows, keywords: "sort windows workspace count tip"),
        SettingEntry(id: "windows.bundleID", title: "Add app by bundle ID", pane: .windows, advanced: true, keywords: "floating wildcard identifier"),
        SettingEntry(id: "windows.home", title: "Home Desktop", pane: .windows, advanced: true, keywords: "spaces desktop workspaces live"),

        SettingEntry(id: "motion.style", title: "Animation style", pane: .motion, keywords: "preset snappy smooth springy bouncy"),
        SettingEntry(id: "motion.preview", title: "Animation preview", pane: .motion, keywords: "play"),
        SettingEntry(id: "motion.bezier", title: "Bezier control points", pane: .motion, advanced: true, keywords: "cubic custom curve"),

        SettingEntry(id: "shortcuts.list", title: "Keyboard shortcuts", pane: .shortcuts, keywords: "keybinds hotkeys bind"),
        SettingEntry(id: "shortcuts.map", title: "Shortcut map", pane: .shortcuts, keywords: "keyboard overview"),
    ]

    /// Settings, then shortcuts, whose words all appear in the query's order-free word list.
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

extension View {
    /// Marks a setting the search can open: the scroll target, lit up when it was just opened.
    func setting(_ id: String, _ ui: SettingsUI) -> some View {
        modifier(SettingAnchor(id: id, ui: ui))
    }
}

private struct SettingAnchor: ViewModifier {
    let id: String
    @ObservedObject var ui: SettingsUI

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.highlight == id ? 1 : 0)
            }
            .id(id)
    }
}
