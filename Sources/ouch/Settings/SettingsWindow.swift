// Settings: the Settings window, its panes enum and the SettingsUI view state.
import AppKit
import SwiftUI

/// Settings, shaped like Zen Browser: traffic lights, a search pill and the panes sit straight on the
/// chrome wash, and the content is one floating pane.
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?
    let doc = ConfigDocument()
    private(set) lazy var library = ConfigLibrary(doc: doc)
    private(set) lazy var ui = SettingsUI(doc: doc)

    func show(pane: Pane?, map: Bool = false) {
        let wasVisible = window?.isVisible ?? false
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 680),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ouch Settings"
            w.isReleasedWhenClosed = false
            let host = NSHostingController(rootView: SettingsView(doc: doc, ui: ui))
            host.sizingOptions = []
            w.contentViewController = host
            ArrowCursor.keep(in: host.view)
            w.setContentSize(NSSize(width: 940, height: 680))
            w.contentMinSize = NSSize(width: 840, height: 540)
            // Pinned: stays above every ordinary window while open, even when another app is active.
            w.level = .floating
            // Settings has no use for full screen: drop the green button and the full-screen behaviour.
            w.clearTitlebar(hiding: [.zoomButton])
            w.collectionBehavior.insert(.fullScreenNone)
            w.delegate = self
            window = w
        }
        if let pane {
            ui.pane = pane
            ui.search = ""
        }
        if map { ui.showMap = true }
        if !wasVisible {
            doc.beginSession()
            ui.beginSession()
            centerOnPointerScreen()
        }
        // Show in the Dock and ⌘-Tab while settings are open, like other menu bar apps do.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        // AppKit hands the keyboard to the first text field, the search; it waits for ⌘K or a click instead.
        if !wasVisible { DispatchQueue.main.async { self.window?.makeFirstResponder(nil) } }
        Tips.shared.paneShown(ui.pane)
    }

    /// Each time the window opens it starts centred on the display under the pointer; while it's
    /// open it can be moved freely. (The tiler always floats our windows, so nothing moves it back.)
    private func centerOnPointerScreen() {
        guard let w = window else { return }
        let area = OuchPanel.pointerScreen().visibleFrame
        let size = NSSize(width: min(w.frame.width, area.width), height: min(w.frame.height, area.height))
        w.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
                   display: false)
    }

    func windowDidUpdate(_ notification: Notification) {
        if window?.standardWindowButton(.zoomButton)?.isHidden == false { window?.standardWindowButton(.zoomButton)?.isHidden = true }
        placeTrafficLights()
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }

    /// Height of the band the traffic lights sit in, above the sidebar's search pill.
    static let titlebarHeight: CGFloat = 48

    /// Insets the close and minimise buttons from the corner and centres them in the taller band.
    private func placeTrafficLights() {
        guard let w = window, let close = w.standardWindowButton(.closeButton), let mini = w.standardWindowButton(.miniaturizeButton),
              let bar = close.superview, let container = bar.superview else { return }
        let h = Self.titlebarHeight
        if container.frame.height != h {
            container.setFrameSize(NSSize(width: container.frame.width, height: h))
            container.setFrameOrigin(NSPoint(x: container.frame.minX, y: (container.superview?.frame.height ?? w.frame.height) - h))
            bar.setFrameSize(NSSize(width: bar.frame.width, height: h))
        }
        let y = (h - close.frame.height) / 2
        for (i, b) in [close, mini].enumerated() {
            let x = 22 + CGFloat(i) * 20
            if b.frame.origin != NSPoint(x: x, y: y) { b.setFrameOrigin(NSPoint(x: x, y: y)) }
        }
    }

    /// Double-clicking the title bar would still zoom; Settings keeps the size it was given.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        ui.endSession()
        Tips.shared.settingsClosed()
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - View state

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", layout = "Layout", windows = "Windows", motion = "Motion", shortcuts = "Shortcuts"
    var id: Self { self }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .layout: "square.grid.2x2"
        case .windows: "macwindow.on.rectangle"
        case .motion: "wand.and.stars"
        case .shortcuts: "keyboard"
        }
    }
    /// The library of saved configs a pane has a selector for.
    var configKind: ConfigKind? {
        switch self { case .motion: .animation; case .shortcuts: .keyboard; default: nil }
    }
}

/// View state lives here instead of in @State (the Command Line Tools ship without SwiftUI's macro plugin).
final class SettingsUI: ObservableObject {
    @Published var pane: Pane = .general
    /// The settings search in the sidebar.
    @Published var search = ""
    /// Filters the shortcut list.
    @Published var shortcutFilter = ""
    @Published var bindMode = "" // which mode the shortcuts pane shows; "" = global
    /// Panes whose Advanced section is open.
    @Published var advancedOpen: Set<Pane> = []
    /// The setting a search result just opened: scrolled to and lit for a moment.
    @Published var highlight: String?
    /// Range and custom rows whose raw editor is open.
    @Published var expanded: Set<UUID> = []
    /// Row to scroll to and flash when the shortcuts pane appears (from the shortcut map or search).
    @Published var reveal: UUID?
    /// The keyboard map is showing in the pane.
    @Published var showMap = false
    @Published var newID = ""
    @Published var previewFlipped = false
    @Published var bezierText = ""
    @Published var linkedPadding = true
    @Published var status = WindowManager.shared.status()
    /// Row whose shortcut is being recorded. Global keybinds are paused meanwhile so the combo
    /// arrives here instead of moving windows.
    @Published var recording: UUID? { didSet { updateMonitor() } }

    private let doc: ConfigDocument
    private var monitor: Any?
    private var timer: Timer?

    init(doc: ConfigDocument) { self.doc = doc }

    func beginSession() {
        let c = doc.config
        linkedPadding = Set([c.paddingTop, c.paddingBottom, c.paddingLeft, c.paddingRight]).count == 1
        refreshStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStatus() }
        timer?.tolerance = 0.2 // coalesces with other wakeups
    }

    func endSession() {
        recording = nil
        showMap = false
        search = ""
        timer?.invalidate()
        timer = nil
    }

    func refreshStatus() { status = WindowManager.shared.status() }

    /// Opens a search result: its pane, its Advanced section if it's hidden there, then lights it up.
    func open(_ entry: SettingEntry) {
        search = ""
        showMap = false
        if let row = entry.bind {
            bindMode = row.submap
            shortcutFilter = ""
            expanded.insert(row.id)
            reveal = row.id
        }
        if entry.advanced { advancedOpen.insert(entry.pane) }
        pane = entry.pane
        highlight = nil
        DispatchQueue.main.async { self.highlight = entry.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            if self?.highlight == entry.id { withAnimation(.easeOut(duration: 0.5)) { self?.highlight = nil } }
        }
    }

    private func updateMonitor() {
        guard recording != nil else {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            Hotkeys.shared.paused = false
            return
        }
        Hotkeys.shared.paused = true
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in guard let self else { return e }; return self.record(e) }
        }
    }

    private func record(_ e: NSEvent) -> NSEvent? {
        // Caps Lock only ever arrives as a modifier change; other modifiers alone aren't a shortcut.
        if e.type == .flagsChanged && e.keyCode != 57 { return e }
        guard let id = recording, let i = doc.binds.firstIndex(where: { $0.id == id }) else { recording = nil; return e }
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let esc = e.keyCode == 53 && flags.isEmpty
        let isRange = BindRange.isRange(doc.binds[i].key)
        if esc && (doc.binds[i].submap.isEmpty || isRange) { // Esc cancels, except on a mode's single-key rows
            recording = nil
            return nil
        }
        guard let name = ConfigDocument.keyName(for: e.keyCode) else { NSSound.beep(); return nil }
        if esc {
            // Esc inside a mode row is a legit key to bind (e.g. to leave the mode).
            doc.binds[i].key = "escape"; doc.binds[i].mods = ""
        } else if isRange {
            doc.binds[i].mods = doc.modsString(for: flags) // range rows: only the modifiers are recorded
        } else {
            doc.binds[i].key = name
            doc.binds[i].mods = doc.modsString(for: flags)
        }
        recording = nil
        return nil
    }
}


/// Asks before a destructive change; the first button is the destructive one.
func confirm(_ title: String, _ detail: String, button: String = "Reset") -> Bool {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = detail
    a.addButton(withTitle: button)
    a.addButton(withTitle: "Cancel")
    a.buttons.first?.hasDestructiveAction = true
    return a.runModal() == .alertFirstButtonReturn
}
