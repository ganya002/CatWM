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
            w.setContentSize(NSSize(width: 940, height: 680))
            w.contentMinSize = NSSize(width: 840, height: 540)
            // Pinned: stays above every ordinary window while open, even when another app is active.
            w.level = .floating
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            // Settings has no use for full screen: drop the green button and the full-screen behaviour.
            w.collectionBehavior.insert(.fullScreenNone)
            w.standardWindowButton(.zoomButton)?.isHidden = true
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
        Tips.shared.paneShown(ui.pane)
    }

    /// Each time the window opens it starts centred on the display under the pointer; while it's
    /// open it can be moved freely. (The tiler always floats our windows, so nothing moves it back.)
    private func centerOnPointerScreen() {
        guard let w = window,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        else { return }
        let area = screen.visibleFrame
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
        SettingEntry(id: "general.modifier", title: "Main modifier", pane: .general, keywords: "mod key option command control super"),
        SettingEntry(id: "general.autoCheck", title: "Check for updates automatically", pane: .general, keywords: "update sparkle"),
        SettingEntry(id: "general.autoDownload", title: "Download updates automatically", pane: .general, keywords: "update sparkle"),
        SettingEntry(id: "general.checkNow", title: "Check for updates", pane: .general, keywords: "update version"),
        SettingEntry(id: "general.beta", title: "Include beta releases", pane: .general, advanced: true, keywords: "update channel early"),
        SettingEntry(id: "general.reset", title: "Reset all settings", pane: .general, keywords: "defaults restore factory"),

        SettingEntry(id: "layout.displays", title: "Layout per display", pane: .layout, keywords: "screen monitor current"),
        SettingEntry(id: "layout.cycle", title: "Layouts in the cycle", pane: .layout, keywords: "order next previous tall wide bsp column"),
        SettingEntry(id: "layout.gaps", title: "Gaps between windows", pane: .layout, keywords: "margin spacing"),
        SettingEntry(id: "layout.gapSize", title: "Gap size", pane: .layout, keywords: "margin spacing points"),
        SettingEntry(id: "layout.padding", title: "Screen padding", pane: .layout, keywords: "edges margin inset"),
        SettingEntry(id: "layout.hud", title: "Show layout name on change", pane: .layout, keywords: "hud overlay"),
        SettingEntry(id: "layout.smartGaps", title: "Smart gaps", pane: .layout, advanced: true, keywords: "single window no gaps"),
        SettingEntry(id: "layout.linked", title: "Same padding on every side", pane: .layout, advanced: true, keywords: "top bottom left right"),
        SettingEntry(id: "layout.builtin", title: "No padding on the built-in display", pane: .layout, advanced: true, keywords: "laptop macbook"),
        SettingEntry(id: "layout.menuBar", title: "Tile over the menu bar", pane: .layout, advanced: true, keywords: "hidden menubar"),
        SettingEntry(id: "layout.resizeStep", title: "Main pane resize step", pane: .layout, advanced: true, keywords: "ratio grow shrink percent"),
        SettingEntry(id: "layout.hudSpaces", title: "Show layout name when switching spaces", pane: .layout, advanced: true, keywords: "hud desktop"),

        SettingEntry(id: "windows.ffm", title: "Focus follows mouse", pane: .windows, keywords: "hover pointer"),
        SettingEntry(id: "windows.mff", title: "Mouse follows focus", pane: .windows, keywords: "pointer cursor warp"),
        SettingEntry(id: "windows.dimOthers", title: "Dim other windows", pane: .windows, keywords: "focus darken inactive spotlight hazeover"),
        SettingEntry(id: "windows.dimStrength", title: "Dim strength", pane: .windows, keywords: "darken amount opacity"),
        SettingEntry(id: "windows.blurOthers", title: "Blur other windows", pane: .windows, keywords: "focus soft inactive spotlight"),
        SettingEntry(id: "windows.blurRadius", title: "Blur radius", pane: .windows, keywords: "soft amount points"),
        SettingEntry(id: "windows.dragSwap", title: "Drag to swap", pane: .windows, keywords: "mouse move"),
        SettingEntry(id: "windows.resizeMain", title: "Resize to adjust the main pane", pane: .windows, keywords: "mouse ratio"),
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

        SettingEntry(id: "shortcuts.list", title: "Keyboard shortcuts", pane: .shortcuts, keywords: "keybinds hotkeys bind"),
        SettingEntry(id: "shortcuts.map", title: "Shortcut map", pane: .shortcuts, keywords: "keyboard overview"),
        SettingEntry(id: "shortcuts.keyboardHelp", title: "Show keyboard help", pane: .shortcuts,
                     keywords: "on-screen hold command cmd caps lock question mark"),
        SettingEntry(id: "shortcuts.keyboardFinish", title: "Keyboard finish", pane: .shortcuts,
                     keywords: "keyboard model colour color auto macbook air pro neo magic"),
        SettingEntry(id: "shortcuts.wasd", title: "Gaming shortcuts (WASD)", pane: .shortcuts, keywords: "reset preset games"),
        SettingEntry(id: "shortcuts.defaults", title: "Restore default shortcuts", pane: .shortcuts, keywords: "reset vim"),
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

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(doc: doc, ui: ui, searchFocused: $searchFocused)
                .frame(width: 228)
            PaneHost(doc: doc, ui: ui)
                .pane()
                .padding(.vertical, 8).padding(.trailing, 8)
        }
        .background(Theme.wash.ignoresSafeArea())
        .overlayPreferenceValue(TipAnchorKey.self) { SettingsTipLayer(anchors: $0) }
        .onChange(of: ui.pane) { _, p in Tips.shared.paneShown(p) }
        .ignoresSafeArea()
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background {
            // ⌘F focuses the settings search.
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
        .sheet(item: $library.sheet) { ConfigSheetView(sheet: $0, library: library) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { library.importFile(url) } }
            }
            return true
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject private var library = SettingsWindow.shared.library

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SettingsWindow.titlebarHeight)
            OSearchField(placeholder: "Search settings", text: $ui.search, shortcut: ["⌘", "F"], focus: searchFocused) {
                if let first = SettingsIndex.search(ui.search, doc: doc).first { ui.open(first) }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .padding(.bottom, 14)
            VStack(spacing: 2) {
                ForEach(Pane.allCases) { p in
                    SideItem(pane: p, on: p == ui.pane && ui.search.isEmpty, badge: badge(p)) {
                        withAnimation(.easeOut(duration: Theme.fast)) {
                            ui.search = ""
                            ui.showMap = false
                            ui.pane = p
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                Text("Config").font(Theme.body(12, .medium)).foregroundStyle(Theme.inkMuted).padding(.leading, 10)
                HStack(spacing: 4) {
                    ConfigSelector(kind: .full, library: library)
                    ConfigTransferMenu(kind: .full, library: library)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Wordmark()
                    Text(version).font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 0)
                    BugReportButton()
                }
                .padding(.leading, 10).padding(.top, 6)
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.bottom, 12)
    }

    private func badge(_ p: Pane) -> SideItem.Badge? {
        switch p {
        case .general where !(ui.status.trusted && ui.status.keybindsActive): .attention
        case .shortcuts where doc.problemCount > 0: .count(doc.problemCount)
        default: nil
        }
    }
}

/// A sidebar item straight on the wash; the selected one is a `surface` pill.
private struct SideItem: View {
    enum Badge { case attention, count(Int) }
    let pane: Pane
    let on: Bool
    let badge: Badge?
    let action: () -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var hover = false
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(on ? Theme.accentInk : Theme.inkMuted)
                    .frame(width: 18)
                Text(pane.rawValue).font(Theme.body(13.5, on ? .medium : .regular)).oneLine()
                Spacer(minLength: 0)
                switch badge {
                case .attention:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.warning)
                        .accessibilityLabel("Needs attention")
                case .count(let n):
                    Text("\(n)").font(Theme.body(11, .medium)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.dangerSoft))
                        .accessibilityLabel("\(n) problems")
                case nil:
                    EmptyView()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).frame(height: 34)
            .background {
                let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
                if on {
                    shape.fill(Theme.surface).elevation(.sm, in: shape)
                } else {
                    shape.fill(Theme.surface.opacity(model.hover ? 0.55 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { model.hover = $0 }
        .animation(.easeOut(duration: Theme.fast), value: model.hover)
        .accessibilityAddTraits(on ? .isSelected : [])
        .tipAnchor("pane.\(pane.rawValue)")
    }
}

/// The logo. It tips like the window on the icon when hovered, and takes a bump when clicked.
private struct Wordmark: View {
    private final class Model: ObservableObject {
        @Published var hover = false
        @Published var bumps = 0
    }
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Ouch").font(Theme.wordmark(19))
            .rotationEffect(.degrees(model.hover && !reduceMotion ? -6 : 0), anchor: .bottomLeading)
            .squish(on: model.bumps)
            .overlay(alignment: .topLeading) {
                ImpactBurst(trigger: model.bumps, size: 15).offset(x: -10, y: -8)
            }
            .animation(Motion.snap, value: model.hover)
            .onHover { model.hover = $0 }
            .onTapGesture { model.bumps += 1 }
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Pane host

private struct PaneHost: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if !ui.search.isEmpty {
                SearchResults(doc: doc, ui: ui)
            } else if ui.showMap {
                ShortcutMap(doc: doc, ui: ui)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content.id(ui.pane)
            }
            StatusPill(doc: doc)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    switch ui.pane {
                    case .general: GeneralPane(doc: doc, ui: ui)
                    case .layout: LayoutPane(doc: doc, ui: ui)
                    case .windows: WindowsPane(doc: doc, ui: ui)
                    case .motion: MotionPane(doc: doc, ui: ui)
                    case .shortcuts: ShortcutsPane(doc: doc, ui: ui)
                    }
                }
                .padding(.horizontal, 36).padding(.top, 22).padding(.bottom, 64)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .onChange(of: ui.highlight) { _, id in
                guard let id else { return }
                // After the Advanced section has had a moment to open.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(Motion.easeOut) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onChange(of: ui.recording) { _, id in
                if let id { withAnimation { proxy.scrollTo("bind.\(id)", anchor: .center) } }
            }
            .onAppear {
                if let id = ui.highlight { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) } }
                guard let id = ui.reveal else { return }
                DispatchQueue.main.async { proxy.scrollTo("bind.\(id)", anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if ui.reveal == id { withAnimation(.easeOut(duration: 0.4)) { ui.reveal = nil } }
                }
            }
        }
    }

    /// Breadcrumb, the 40pt light title, and the pane's config selector.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Settings")
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                Text(ui.pane.rawValue)
            }
            .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
            HStack(alignment: .center, spacing: 8) {
                Text(ui.pane.rawValue).font(Theme.display(40)).tracking(-1).oneLine()
                Spacer(minLength: 12)
                if let kind = ui.pane.configKind {
                    ConfigSelector(kind: kind, library: library, width: 180)
                    ConfigTransferMenu(kind: kind, library: library)
                }
            }
        }
    }
}

// MARK: - Search results

private struct SearchResults: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let results = SettingsIndex.search(ui.search, doc: doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    // The same breadcrumb as the panes, so the title doesn't jump when results replace a pane.
                    HStack(spacing: 6) {
                        Text("Settings")
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        Text("Search")
                    }
                    .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                    Text("“\(ui.search)”").font(Theme.display(40)).tracking(-1).oneLine()
                }
                if results.isEmpty {
                    Text("Nothing matches. Try another word, like “gaps” or “focus”.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                ForEach(Pane.allCases) { p in
                    let here = results.filter { $0.pane == p }
                    if !here.isEmpty {
                        OGroup(p.rawValue) {
                            ForEach(here) { r in ResultRow(entry: r, first: r.id == results.first?.id) { ui.open(r) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 36).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ResultRow: View {
    let entry: SettingEntry
    let first: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.bind != nil ? "command" : entry.pane.icon)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.accentInk).frame(width: 18)
                Text(entry.title).font(Theme.body(14)).oneLine()
                if entry.advanced {
                    Text("Advanced").font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                Spacer(minLength: 8)
                if first { Text("↩").font(Theme.keys(12)).foregroundStyle(Theme.inkMuted) }
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .opacity(hover.on ? 1 : 0)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover.on ? Theme.hover : .clear))
            .padding(.horizontal, -10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

// MARK: - Status

/// A small glass capsule over the bottom of the pane: a brief "Saved" when a change lands, problems
/// while there are any, and "Undo All Changes" once something changed since the window opened.
private struct StatusPill: View {
    @ObservedObject var doc: ConfigDocument
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var saved = false
        private var hide: DispatchWorkItem?

        func flash() {
            withAnimation(Motion.easeOut) { saved = true }
            hide?.cancel()
            let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: 0.3)) { self?.saved = false } }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        }
    }

    private enum Message: Equatable { case error(String), problems(Int), skipped(Int), saved }

    /// What to say, most urgent first. Saving itself takes a few milliseconds, so it isn't announced.
    private var message: Message? {
        if let err = doc.saveError { return .error(err) }
        if doc.problemCount > 0 { return .problems(doc.problemCount) }
        if model.saved { return .saved }
        if !doc.fileErrors.isEmpty { return .skipped(doc.fileErrors.count) }
        return nil
    }

    var body: some View {
        let message = message, undo = doc.hasChangesSinceOpen
        Group {
            if message != nil || undo {
                HStack(spacing: 10) {
                    if let message { label(message).transition(.opacity) }
                    if message != nil && undo { Rectangle().fill(Theme.hairline).frame(width: 1, height: 16) }
                    if undo {
                        Button { doc.undoAllChanges() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .semibold))
                                Text("Undo All Changes").font(Theme.body(12.5, .medium)).oneLine()
                            }
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(Theme.well))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(PressScale())
                        .help("Go back to how things were when you opened Settings")
                    }
                }
                .padding(.leading, message == nil ? 5 : 14).padding(.trailing, undo ? 5 : 14)
                .frame(height: 36)
                .floatingGlass(Capsule())
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.easeOut, value: message)
        .animation(Motion.easeOut, value: undo)
        .onChange(of: doc.isDirty) { was, now in
            if was && !now && doc.saveError == nil { model.flash() }
        }
    }

    @ViewBuilder private func label(_ m: Message) -> some View {
        switch m {
        case .error(let err):
            OStatus(kind: .danger, text: "Couldn't save: \(err)").help(err)
        case .problems(let n):
            OStatus(kind: .warning, text: "Fix \(n) shortcut\(n == 1 ? "" : "s") to save")
        case .skipped(let n):
            OStatus(kind: .warning, text: "\(n) line\(n == 1 ? "" : "s") in the config file skipped")
                .help(doc.fileErrors.joined(separator: "\n"))
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.success)
                Text("Saved").font(Theme.body(12.5, .medium)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

// MARK: - Advanced

/// The collapsed section at the bottom of a pane, holding what it doesn't need to show up front.
struct AdvancedSection<Content: View>: View {
    let pane: Pane
    @ObservedObject var ui: SettingsUI
    @ViewBuilder var content: Content

    var body: some View {
        let open = ui.advancedOpen.contains(pane)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.easeOut) {
                    if open { ui.advancedOpen.remove(pane) } else { ui.advancedOpen.insert(pane) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced").font(Theme.body(12, .medium)).tracking(0.24)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 6)
                }
                .foregroundStyle(open ? Theme.accentInk : Theme.inkMuted)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide advanced settings" : "Show advanced settings")
            if open {
                VStack(alignment: .leading, spacing: 30) { content }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Permissions

enum Permissions {
    /// Input Monitoring lets Caps Lock shortcuts fire at the real key press (see Hotkeys.startRawCaps).
    /// Optional: without it they still work, after macOS's own Caps Lock delay.
    static var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// Starts the Input Monitoring grant flow: the first request shows macOS's prompt (and lists us),
    /// later ones go straight to the list. Either way the guide walks through it.
    static func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        let first = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeUnknown
        if first { IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        PermissionGuide.shared.show(.inputMonitoring)
        DispatchQueue.main.asyncAfter(deadline: .now() + (first ? 0.8 : 0)) {
            if !inputMonitoringGranted { openInputMonitoringPane() }
        }
    }

    private static func openInputMonitoringPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Drops a stale Input Monitoring entry (same story as `clearStaleEntry`) and starts over.
    static func resetInputMonitoring() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "ListenEvent", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
        requestInputMonitoring()
    }

    /// Whether this launch already asked macOS to list us (which also shows its own alert). Asking again
    /// would clear the entry it just added and stack another alert, so later requests only reopen Settings.
    private static var prompted = false

    static func openSettings() {
        openPane()
        PermissionGuide.shared.show()
    }

    private static func openPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Drops any Accessibility entry left by an older build or moved copy; it would show as
    /// "on" in System Settings while macOS rejects this binary.
    static func clearStaleEntry() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.ouch"]
        try? p.run()
        p.waitUntilExit()
    }

    /// Starts the grant flow: the first time, from a clean slate (clear stale entry, prompt so we're
    /// listed); after that just Settings + guide again.
    static func request() {
        guard !AXIsProcessTrusted() else { return }
        if prompted { openSettings() } else { promptThenSettings() }
    }

    static func reset() { promptThenSettings() }

    /// macOS only adds us to the list when its alert's "Open System Settings" is clicked, so while that
    /// alert is up the guide points at it instead of opening a list we aren't in yet. If no alert comes
    /// (macOS shows it once per entry), open Settings ourselves.
    private static func promptThenSettings() {
        prompt()
        PermissionGuide.shared.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if PermissionGuide.alertFrame() == nil, !AXIsProcessTrusted() { openPane() }
        }
    }

    private static func prompt() {
        prompted = true
        clearStaleEntry()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Closes the System Settings window (needs Accessibility, which we have by now).
    static func closeSettingsWindows() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
        for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
            window.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
        }
    }

    /// The prompt shows macOS's own "would like to control this computer" alert, which stays up after
    /// the switch is turned on in Settings. Once we're trusted we can reach it: press its default
    /// button ("Open System Settings", harmless; Settings is closed right after). Never "Deny".
    static func dismissSystemAlert() {
        guard AXIsProcessTrusted() else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.accessibility.universalAccessAuthWarn") {
            for window in AXUIElementCreateApplication(app.processIdentifier).elements(kAXWindowsAttribute) {
                window.element(kAXDefaultButtonAttribute)?.perform(kAXPressAction)
            }
        }
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

/// Report a Bug… at the foot of the sidebar, with the crash dot while a crash report is waiting.
private struct BugReportButton: View {
    @StateObject private var crashed = Flag()

    var body: some View {
        OIconButton(symbol: "ladybug", label: crashed.on ? "Report a bug: Ouch crashed" : "Report a bug") { CrashWatch.openReport() }
            .overlay(alignment: .topTrailing) {
                if crashed.on { NotificationDot().offset(x: -6, y: 6).allowsHitTesting(false) }
            }
            .frame(width: 30) // the share button above is 30 wide: centred under it
            .onAppear { crashed.on = CrashWatch.pending != nil }
            .onReceive(NotificationCenter.default.publisher(for: .crashPendingChanged)) { _ in
                crashed.on = CrashWatch.pending != nil
            }
    }
}
