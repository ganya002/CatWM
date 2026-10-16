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
    static let all: [SettingEntry] = [
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
        SettingEntry(id: "layout.gaps", title: "Gaps between windows", pane: .layout, keywords: "margin spacing"),
        SettingEntry(id: "layout.gapSize", title: "Gap size", pane: .layout, keywords: "margin spacing points"),
        SettingEntry(id: "layout.padding", title: "Screen padding", pane: .layout, keywords: "edges margin inset"),
        SettingEntry(id: "layout.hud", title: "Show layout name on change", pane: .layout, keywords: "hud overlay"),
        SettingEntry(id: "layout.smartGaps", title: "Smart gaps", pane: .layout, keywords: "single window no gaps"),
        SettingEntry(id: "layout.linked", title: "Same padding on every side", pane: .layout, advanced: true, keywords: "top bottom left right"),
        SettingEntry(id: "layout.builtin", title: "No padding on the built-in display", pane: .layout, keywords: "laptop macbook"),
        SettingEntry(id: "layout.menuBar", title: "Ignore menu bar when tiling", pane: .layout, advanced: true, keywords: "tile over hidden menubar"),
        SettingEntry(id: "layout.resizeStep", title: "Main pane resize step", pane: .layout, keywords: "ratio grow shrink percent"),
        SettingEntry(id: "layout.hudSpaces", title: "Show layout name when switching spaces", pane: .layout, advanced: true, keywords: "hud desktop"),

        SettingEntry(id: "windows.ffm", title: "Focus follows mouse", pane: .windows, keywords: "hover pointer"),
        SettingEntry(id: "windows.ffmModeOnly", title: "Focus follows mouse only in window mode", pane: .windows,
                     keywords: "hover pointer submap"),
        SettingEntry(id: "windows.mff", title: "Mouse follows focus", pane: .windows, keywords: "pointer cursor warp"),
        SettingEntry(id: "windows.dimOthers", title: "Dim other windows", pane: .windows, keywords: "focus darken inactive spotlight hazeover"),
        SettingEntry(id: "windows.dimStrength", title: "Dim strength", pane: .windows, keywords: "darken amount opacity"),
        SettingEntry(id: "windows.blurOthers", title: "Blur other windows", pane: .windows, keywords: "focus soft inactive spotlight"),
        SettingEntry(id: "windows.blurRadius", title: "Blur radius", pane: .windows, keywords: "soft amount points"),
        SettingEntry(id: "windows.dragSwap", title: "Drag to swap", pane: .windows, keywords: "mouse move"),
        SettingEntry(id: "windows.cursorActions", title: "Quick actions at the pointer", pane: .windows,
                     keywords: "cursor mouse menu window mode tap modifier command dot indicator"),
        SettingEntry(id: "windows.resizeMain", title: "Drag window edges to resize the main pane", pane: .windows, keywords: "mouse ratio"),
        SettingEntry(id: "windows.floatingMode", title: "Floating apps", pane: .windows, keywords: "float exclude blacklist whitelist tile only"),
        SettingEntry(id: "windows.workspaces", title: "Use Ouch workspaces", pane: .windows, keywords: "spaces desktops virtual"),
        SettingEntry(id: "windows.sortStrategy", title: "Sort windows by", pane: .windows, keywords: "group organize task app focus panel"),
        SettingEntry(id: "windows.sortNudge", title: "Suggest sorting a crowded workspace", pane: .windows, keywords: "tip packed many windows organize"),
        SettingEntry(id: "windows.sortCrowded", title: "Crowded from", pane: .windows, keywords: "sort windows workspace count tip"),
        SettingEntry(id: "windows.newMain", title: "New windows become main", pane: .windows, advanced: true, keywords: "open"),
        SettingEntry(id: "windows.floatSmall", title: "Float small windows", pane: .windows, advanced: true, keywords: "dialogs panels"),
        SettingEntry(id: "windows.bundleID", title: "Add app by bundle ID", pane: .windows, advanced: true, keywords: "floating wildcard identifier"),
        SettingEntry(id: "windows.stay", title: "Stay on this workspace when closing a window", pane: .windows, advanced: true, keywords: "close jump"),
        SettingEntry(id: "windows.home", title: "Home Desktop", pane: .windows, advanced: true, keywords: "spaces desktop workspaces live"),

        SettingEntry(id: "motion.style", title: "Animation style", pane: .motion, keywords: "preset snappy smooth springy bouncy"),
        SettingEntry(id: "motion.animate", title: "Animate windows", pane: .motion, keywords: "animation off motion"),
        SettingEntry(id: "motion.duration", title: "Duration", pane: .motion, keywords: "speed time milliseconds animation"),
        SettingEntry(id: "motion.preview", title: "Animation preview", pane: .motion, keywords: "play"),
        SettingEntry(id: "motion.curve", title: "Curve", pane: .motion, advanced: true, keywords: "easing ease spring bounce overshoot linear"),
        SettingEntry(id: "motion.bounce", title: "Bounciness", pane: .motion, advanced: true, keywords: "spring overshoot"),
        SettingEntry(id: "motion.bezier", title: "Bezier control points", pane: .motion, advanced: true, keywords: "cubic custom curve"),
        SettingEntry(id: "motion.panels", title: "Panel animation", pane: .motion, advanced: true,
                     keywords: "sort windows keyboard help rise pop focus tile draw open appear"),
        SettingEntry(id: "motion.modeEffect", title: "Window mode effect", pane: .motion, advanced: true,
                     keywords: "border edge draw ripple corners submap indicator"),

        SettingEntry(id: "shortcuts.list", title: "Keyboard shortcuts", pane: .shortcuts, keywords: "keybinds hotkeys bind"),
        SettingEntry(id: "shortcuts.map", title: "Shortcut map", pane: .shortcuts, keywords: "keyboard overview"),
        SettingEntry(id: "shortcuts.keyboardHelp", title: "Show keyboard help", pane: .shortcuts,
                     keywords: "on-screen hold command cmd caps lock question mark"),
        SettingEntry(id: "shortcuts.keyboardFinish", title: "Keyboard finish", pane: .shortcuts,
                     keywords: "keyboard model colour color auto macbook air pro neo magic"),
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
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.highlight == id ? 1 : 0)
            }
            .id(id)
    }
}
