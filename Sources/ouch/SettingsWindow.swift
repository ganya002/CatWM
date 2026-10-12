import AppKit
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private(set) var window: NSWindow?
    let doc = ConfigDocument()
    private(set) lazy var ui = SettingsUI(doc: doc)

    func show(pane: Pane?) {
        let wasVisible = window?.isVisible ?? false
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Ouch Settings"
            w.isReleasedWhenClosed = false
            // Unified toolbar over a native sidebar, like Notes. The title stays hidden because each
            // pane draws its own heading; SwiftUI fills the toolbar (search field on Keyboard Shortcuts).
            let host = NSHostingController(rootView: SettingsView(doc: doc, ui: ui))
            host.sceneBridgingOptions = [.toolbars]
            host.sizingOptions = []
            w.contentViewController = host
            w.setContentSize(NSSize(width: 920, height: 660))
            w.contentMinSize = NSSize(width: 820, height: 520)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            // Settings has no use for full screen: drop the green button and the full-screen behaviour.
            w.collectionBehavior.insert(.fullScreenNone)
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.delegate = self
            window = w
            Self.hideSplitDivider
        }
        if let pane { ui.pane = pane }
        if !wasVisible {
            doc.beginSession()
            ui.beginSession()
            centerOnPointerScreen()
        }
        // Show in the Dock and ⌘-Tab while settings are open, like other menu bar apps do.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// The split view between sidebar and detail draws a dark 1pt divider; the panes already differ in
    /// background, so Settings' own split view gets a clear divider (other split views are untouched).
    private static let hideSplitDivider: Void = {
        let sel = #selector(getter: NSSplitView.dividerColor)
        guard let m = class_getInstanceMethod(NSSplitView.self, sel) else { return }
        typealias Getter = @convention(c) (AnyObject, Selector) -> NSColor
        let original = unsafeBitCast(method_getImplementation(m), to: Getter.self)
        let block: @convention(block) (NSSplitView) -> NSColor = { view in
            view.window === SettingsWindow.shared.window ? .clear : original(view, sel)
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }()

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

    /// AppKit brings the zoom button back whenever SwiftUI rebuilds the toolbar (e.g. the search
    /// field on Keyboard Shortcuts), so hide it again on every update.
    func windowDidUpdate(_ notification: Notification) {
        if window?.standardWindowButton(.zoomButton)?.isHidden == false { window?.standardWindowButton(.zoomButton)?.isHidden = true }
    }

    /// Double-clicking the title bar would still zoom; Settings keeps the size it was given.
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func windowWillClose(_ notification: Notification) {
        ui.endSession()
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - View state

enum Pane: String, CaseIterable, Identifiable {
    case overview = "Overview", layouts = "Layouts", gaps = "Gaps & Padding", behavior = "Behavior"
    case floating = "Floating Windows", animation = "Animation", keybinds = "Keyboard Shortcuts", advanced = "Advanced"
    var id: Self { self }

    var icon: String {
        switch self {
        case .overview: "rectangle.split.3x1.fill"
        case .layouts: "square.grid.2x2.fill"
        case .gaps: "square.dashed"
        case .behavior: "cursorarrow"
        case .floating: "macwindow.on.rectangle"
        case .animation: "wand.and.stars"
        case .keybinds: "command"
        case .advanced: "wrench.fill"
        }
    }
    var color: Color {
        switch self {
        case .overview: .blue
        case .layouts: .indigo
        case .gaps: .teal
        case .behavior: .orange
        case .floating: .purple
        case .animation: .pink
        case .keybinds: .gray
        case .advanced: .brown
        }
    }
}

/// View state lives here instead of in @State (the Command Line Tools ship without SwiftUI's macro plugin).
final class SettingsUI: ObservableObject {
    @Published var pane: Pane? = .overview
    @Published var search = ""
    @Published var bindMode = "" // which mode the shortcuts pane shows; "" = global
    @Published var newID = ""
    @Published var previewFlipped = false
    @Published var linkedPadding = true
    @Published var dragAnywhere = DragAnywhere.isEnabled
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
        dragAnywhere = DragAnywhere.isEnabled
        refreshStatus()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshStatus() }
    }

    func endSession() {
        recording = nil
        timer?.invalidate()
        timer = nil
    }

    func refreshStatus() { status = WindowManager.shared.status() }

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

// MARK: - Root

struct SettingsView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let pane = ui.pane ?? .overview
        NavigationSplitView {
            Sidebar(doc: doc, ui: ui)
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(220)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.rawValue).font(Theme.heading(22))
                .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 12)
                Group {
                    switch pane {
                    case .overview: OverviewPane(doc: doc, ui: ui)
                    case .layouts: LayoutsPane(doc: doc)
                    case .gaps: GapsPane(doc: doc, ui: ui)
                    case .behavior: BehaviorPane(doc: doc, ui: ui)
                    case .floating: FloatingPane(doc: doc, ui: ui)
                    case .animation: AnimationPane(doc: doc, ui: ui)
                    case .keybinds: KeybindsPane(doc: doc, ui: ui)
                    case .advanced: AdvancedPane(doc: doc)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                StatusBar(doc: doc)
            }
            .background(Theme.window)
            .modifier(SeamlessToolbar())
        }
        .font(Theme.body())
    }
}

/// Lets the detail background run up under the (empty) toolbar instead of a separate strip.
private struct SeamlessToolbar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            content
        }
    }
}

/// Standard source-list sidebar, like Notes and System Settings.
private struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        List(Pane.allCases, selection: $ui.pane) { p in
            HStack(spacing: 8) {
                IconTile(symbol: p.icon, color: p.color, size: 22)
                Text(p.rawValue)
                Spacer(minLength: 0)
                if p == .overview && !(ui.status.trusted && ui.status.keybindsActive) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white, .orange)
                        .accessibilityLabel("Needs attention")
                } else if p == .keybinds && doc.problemCount > 0 {
                    Text("\(doc.problemCount)").font(Theme.body(11, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(.red))
                }
            }
            .tag(p)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Wordmark()
                Text(version).font(Theme.body(11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
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
        Text("Ouch").font(Theme.display(22))
            .rotationEffect(.degrees(model.hover && !reduceMotion ? -6 : 0), anchor: .bottomLeading)
            .squish(on: model.bumps)
            .overlay(alignment: .topLeading) {
                ImpactBurst(trigger: model.bumps, size: 16).offset(x: -10, y: -8)
            }
            .animation(Motion.snap, value: model.hover)
            .onHover { model.hover = $0 }
            .onTapGesture { model.bumps += 1 }
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StatusBar: View {
    @ObservedObject var doc: ConfigDocument

    var body: some View {
        HStack(spacing: 10) {
            if let err = doc.saveError {
                dot(.red)
                Text("Couldn't save: \(err)").foregroundStyle(.red)
            } else if doc.problemCount > 0 {
                dot(.orange)
                Text("Fix \(doc.problemCount) shortcut\(doc.problemCount == 1 ? "" : "s") to save your changes").foregroundStyle(.orange)
            } else if doc.isDirty {
                ProgressView().controlSize(.small).scaleEffect(0.8).frame(width: 14, height: 14)
                Text("Saving…").foregroundStyle(Theme.secondary)
            } else if !doc.fileErrors.isEmpty {
                dot(.orange)
                Text("\(doc.fileErrors.count) line\(doc.fileErrors.count == 1 ? "" : "s") in the config file were skipped")
                    .foregroundStyle(.orange)
                    .help(doc.fileErrors.joined(separator: "\n"))
            } else {
                EmptyView()
            }
            Spacer()
            if doc.hasChangesSinceOpen {
                Button("Undo All Changes") { doc.undoAllChanges() }
            }
        }
        .font(Theme.body(12.5))
        .padding(.leading, 24).padding(.trailing, 16)
        .frame(height: 38)
        .background(Theme.statusBar)
        .overlay(alignment: .top) { Divider() }
    }

    private func dot(_ c: Color) -> some View { Circle().fill(c).frame(width: 8, height: 8) }
}

// MARK: - Shared components

/// Scrolling pane body with the design's insets.
private struct PaneScroll<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content }
                .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    /// Disabled and faded, like the design's inactive rows.
    func dimmed(_ off: Bool) -> some View { disabled(off).opacity(off ? 0.4 : 1) }
}

private struct NumberRow: View {
    let title: String
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 0...60
    @Environment(\.isEnabled) private var enabled

    /// Whole points, clamped to the range, so the slider, field and stepper never disagree.
    private var points: Binding<Double> {
        Binding(get: { Double(value) }, set: { v in
            let r = CGFloat(v.rounded())
            let clamped = min(range.upperBound, max(range.lowerBound, r))
            if clamped != value { value = clamped }
        })
    }

    var body: some View {
        Row(title, vertical: 7) {
            HStack(spacing: 8) {
                // No `step:`: on macOS it draws a tick mark per step and makes the knob jump. The binding rounds instead.
                Slider(value: points, in: Double(range.lowerBound)...Double(range.upperBound))
                    .controlSize(.small)
                    .frame(width: 180)
                    .accessibilityLabel(title)
                    .accessibilityValue("\(Int(value)) points")
                HStack(spacing: 2) {
                    TextField(title, value: points, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 44)
                    Stepper(title, value: points, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                        .labelsHidden()
                }
                Text("pt").foregroundStyle(.secondary)
            }
        }
        .opacity(enabled ? 1 : 0.4)
    }
}

private extension Layout {
    var blurb: String {
        switch self {
        case .tall: "Main on the left, the rest stacked on the right"
        case .tallRight: "Main on the right, the rest stacked on the left"
        case .wide: "Main on top, the rest side by side below"
        case .middleWide: "Main in the middle, the rest split left and right"
        case .fullscreen: "Every window fills the screen"
        case .column: "Equal-width columns"
        case .row: "Equal-height rows"
        case .floating: "Leave windows where you put them"
        case .bsp: "Each window splits the space of the previous one"
        case .threeColumnLeft: "Main on the left, two columns to its right"
        case .threeColumnMiddle: "Main in the middle column"
        case .threeColumnRight: "Main on the right, two columns to its left"
        case .twoPane: "Main on the left, one other window on the right"
        case .twoPaneRight: "Main on the right, one other window on the left"
        case .widescreenTall: "Main windows side by side, the rest stacked right"
        case .widescreenTallRight: "Main windows side by side, the rest stacked left"
        }
    }
}

// MARK: - Overview

private struct OverviewPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        let s = ui.status
        PaneScroll {
            Card(padding: 14) { hero(s) }

            if s.trusted && !s.screens.isEmpty {
                Block("Displays") {
                    Card {
                        ForEach(s.screens, id: \.uuid) { screen in
                            HStack(spacing: 12) {
                                LayoutThumbnail(layout: screen.layout, selected: true).frame(width: 64, height: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(screen.workspace.isEmpty ? screen.name : "\(screen.name) · Workspace \(screen.workspace)")
                                }
                                Spacer(minLength: 0)
                                PopUp(title: "Layout for \(screen.name)", options: Layout.allCases.map { ($0, $0.title) }, selection: Binding(get: { screen.layout }, set: { l in
                                    WindowManager.shared.setLayout(l, screen: screen.uuid)
                                    ui.refreshStatus()
                                }))
                            }
                            .padding(.vertical, 9)
                        }
                    }
                }
            }

            Block("Quick settings") {
                Card {
                    SwitchRow(title: "Open at login", isOn: loginBinding)
                    if ui.status.loginNeedsApproval { LoginApprovalRow() }
                    if !s.inputMonitoring { InputMonitoringRow() }
                    SwitchRow(title: "Tiling", isOn: Binding(get: { ui.status.tilingEnabled }, set: { _ in
                        WindowManager.shared.toggleTiling()
                        ui.refreshStatus()
                    }))
                    .disabled(!s.running)
                    SwitchRow(title: "Focus follows mouse", isOn: $doc.config.focusFollowsMouse)
                    SwitchRow(title: "Mouse follows focus", isOn: $doc.config.mouseFollowsFocus)
                    SwitchRow(title: "Animate windows", isOn: $doc.config.animate)
                    Row("Main modifier") {
                        PopUp(title: "Main modifier", options: modifierOptions, selection: Binding(get: { doc.modValue }, set: { doc.modValue = $0 }))
                    }
                }
            }

            Block("Updates") {
                Card {
                    if updater.isConfigured {
                        SwitchRow(title: "Check for updates automatically",
                                  isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                        SwitchRow(title: "Download updates automatically",
                                  isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                            .disabled(!updater.automaticallyChecks)
                        SwitchRow(title: "Include beta releases", isOn: Binding(get: { updater.receivesBeta }, set: { updater.receivesBeta = $0 }))
                        Row(updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet",
                            vertical: 8) {
                            Button("Check Now") { updater.checkForUpdates() }
                        }
                    } else {
                        Text("This build has no update feed. Release builds published with Amore update themselves.")
                            .foregroundStyle(Theme.secondary)
                            .padding(.vertical, 9)
                    }
                }
            }

            AmoreCredit().frame(maxWidth: .infinity)
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(get: { ui.status.launchAtLogin || ui.status.loginNeedsApproval }, set: { on in
            LoginItem.set(on)
            ui.refreshStatus()
        })
    }

    private var modifierOptions: [(value: String, label: String)] {
        var o = ConfigDocument.modifierChoices.map { (value: $0.value, label: $0.label) }
        if !o.contains(where: { $0.value == doc.modValue }) { o.append((doc.modValue, doc.modValue)) }
        return o
    }

    /// One layout for every state, so the icon stays put (and can bump) when access is granted.
    private func hero(_ s: WindowManager.Status) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                statusIcon(s)
                VStack(alignment: .leading, spacing: 3) {
                    Text(!s.trusted ? "Ouch needs Accessibility access" : !s.tilingEnabled ? "Tiling is paused"
                         : s.keybindsActive ? "Ouch is running" : "Keyboard shortcuts aren't active")
                        .font(Theme.heading(21))
                        .contentTransition(.opacity)
                    Text(s.trusted ? summary(s) : "macOS only lets apps move other apps' windows with this permission.")
                        .foregroundStyle(Theme.secondary)
                        .contentTransition(.numericText())
                }
                Spacer()
                if s.trusted && !s.keybindsActive {
                    Button("Retry") { Hotkeys.shared.restart(); ui.refreshStatus() }
                }
            }
            if !s.trusted {
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Click Open Accessibility Settings. A guide appears next to System Settings.")
                    step(2, "Turn on Ouch in the list.")
                    step(3, "Still not working after a rebuild? Click Reset Permission, then turn it on again.")
                }
                .font(Theme.body(12.5))
                HStack(spacing: 8) {
                    Button("Open Accessibility Settings") { Permissions.request() }.buttonStyle(.borderedProminent)
                    Button("Reset Permission") { Permissions.reset() }
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Waiting…").font(Theme.body(11)).foregroundStyle(Theme.secondary)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: s.trusted)
        .animation(.easeOut(duration: 0.2), value: summary(s))
    }

    /// The app icon with a status badge. Going live (access granted, tiling back on) gives it a bump.
    private func statusIcon(_ s: WindowManager.Status) -> some View {
        let live = s.trusted && s.keybindsActive && s.tilingEnabled
        let badge = !s.trusted ? "lock.circle.fill" : live ? "checkmark.circle.fill"
            : s.keybindsActive ? "pause.circle.fill" : "exclamationmark.circle.fill"
        return BadgedAppIcon(badge: badge, color: live ? .green : .orange, size: 48)
            .squish(on: live, when: live)
            .overlay(alignment: .topLeading) {
                ImpactBurst(trigger: live, size: 22).offset(x: -12, y: -12).opacity(live ? 1 : 0)
            }
    }

    private func summary(_ s: WindowManager.Status) -> String {
        let w = "\(s.tiled) tiled window\(s.tiled == 1 ? "" : "s")"
        let f = s.floating > 0 ? " · \(s.floating) floating" : ""
        let d = " · \(s.screens.count) display\(s.screens.count == 1 ? "" : "s")"
        return w + f + d
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(Theme.body(11, .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct InputMonitoringRow: View {
    var body: some View {
        Row {
            VStack(alignment: .leading, spacing: 2) {
                Text("Instant Caps Lock shortcuts")
                Text("Allow Input Monitoring so Super + Caps Lock fires right away instead of after a hold.")
                    .font(Theme.body(11)).foregroundStyle(Theme.secondary)
            }
        } control: {
            Button("Allow…") { Permissions.requestInputMonitoring() }
        }
    }
}

private struct LoginApprovalRow: View {
    var body: some View {
        Row {
            Label("macOS is waiting for you to allow Ouch in Login Items", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange).font(Theme.body(12.5))
        } control: {
            Button("Open Login Items") { LoginItem.openSettings() }
        }
    }
}

/// Tiny "shipped with" credit; the heart gives a little hop on hover.
private struct AmoreCredit: View {
    private final class Hover: ObservableObject { @Published var on = false }
    @StateObject private var hover = Hover()

    var body: some View {
        let hovering = hover.on
        return Link(destination: URL(string: "https://amore.computer")!) {
            HStack(spacing: 4) {
                Text("shipped with")
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .symbolEffect(.bounce, value: hovering)
                    .shadow(color: .pink.opacity(hovering ? 0.7 : 0), radius: 4)
                Text("Amore").fontWeight(.bold)
            }
            .font(Theme.body(10))
            .foregroundStyle(.primary.opacity(hovering ? 0.85 : 0.3))
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help("Updates delivered by Amore")
    }
}

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

// MARK: - Layouts

private struct LayoutsPane: View {
    @ObservedObject var doc: ConfigDocument
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaneScroll(spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cycle order").font(Theme.heading(16))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(doc.config.layouts.enumerated()), id: \.element) { i, l in
                            orderChip(i, l)
                        }
                    }
                    .padding(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))

            VStack(alignment: .leading, spacing: 10) {
                Text("All layouts").font(Theme.heading(16))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                    ForEach(Layout.allCases, id: \.self) { card($0) }
                }
            }
        }
    }

    private func orderChip(_ i: Int, _ l: Layout) -> some View {
        VStack(spacing: 6) {
            LayoutThumbnail(layout: l, selected: true).frame(width: 84, height: 52)
            Text("\(i + 1). \(l.title)").font(Theme.body(11, .medium)).lineLimit(1).frame(maxWidth: 96)
            HStack(spacing: 2) {
                arrow("chevron.left", enabled: i > 0, help: "Move earlier") { move(i, by: -1) }
                arrow("chevron.right", enabled: i < doc.config.layouts.count - 1, help: "Move later") { move(i, by: 1) }
            }
        }
        .frame(width: 104)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func move(_ i: Int, by d: Int) {
        withAnimation(Motion.snap(reduceMotion)) { doc.config.layouts.swapAt(i, i + d) }
    }

    private func arrow(_ symbol: String, enabled: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.primary.opacity(enabled ? 0.7 : 0.2))
                .frame(width: 22, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private func card(_ l: Layout) -> some View {
        let index = doc.config.layouts.firstIndex(of: l)
        let on = index != nil
        let locked = on && doc.config.layouts.count == 1
        return Button {
            withAnimation(Motion.snap(reduceMotion)) {
                if let index { if !locked { doc.config.layouts.remove(at: index) } } else { doc.config.layouts.append(l) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                LayoutThumbnail(layout: l, selected: on)
                    .frame(height: 86)
                    .squish(on: on, when: on)
                    .overlay(alignment: .topTrailing) {
                        if let index {
                            Text("\(index + 1)").font(Theme.body(11, .bold)).foregroundStyle(.white)
                                .contentTransition(.numericText())
                                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                                .padding(5)
                                .transition(.scale(scale: 0.4).combined(with: .opacity))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        ImpactBurst(trigger: on, size: 22).offset(x: -9, y: -9).opacity(on ? 1 : 0)
                    }
                Text(l.title).font(Theme.body(12.5, .semibold)).foregroundStyle(.primary).padding(.top, 8)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Color.accentColor.opacity(0.1) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(on ? Color.accentColor : Theme.hairline, lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(locked ? "At least one layout has to stay in the cycle" : "\(l.blurb). \(on ? "Click to remove from the cycle" : "Click to add to the cycle")")
    }
}

// MARK: - Gaps

private struct GapsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var allPadding: Binding<CGFloat> {
        Binding(get: { doc.config.paddingTop }, set: { v in
            doc.config.paddingTop = v; doc.config.paddingBottom = v; doc.config.paddingLeft = v; doc.config.paddingRight = v
        })
    }

    var body: some View {
        let c = doc.config
        PaneScroll {
            Card(padding: 14) {
                GapsPreview(config: c, layout: c.layouts.first { ![.floating, .fullscreen].contains($0) } ?? .tall)
                    .frame(width: 368, height: 230)
                    .frame(maxWidth: .infinity)
            }
            Block("Between windows") {
                Card {
                    SwitchRow(title: "Gaps between windows", isOn: $doc.config.windowMargins)
                    NumberRow(title: "Gap", value: $doc.config.windowMarginSize).disabled(!c.windowMargins)
                    SwitchRow(title: "Smart gaps", isOn: $doc.config.smartWindowMargins)
                        .disabled(!c.windowMargins)
                }
            }
            Block("Screen edges") {
                Card {
                    SwitchRow(title: "Same padding on every side", isOn: Binding(get: { ui.linkedPadding }, set: { on in
                        ui.linkedPadding = on
                        if on { allPadding.wrappedValue = c.paddingTop }
                    }))
                    if ui.linkedPadding {
                        NumberRow(title: "Padding", value: allPadding)
                    } else {
                        NumberRow(title: "Top", value: $doc.config.paddingTop)
                        NumberRow(title: "Bottom", value: $doc.config.paddingBottom)
                        NumberRow(title: "Left", value: $doc.config.paddingLeft)
                        NumberRow(title: "Right", value: $doc.config.paddingRight)
                    }
                    SwitchRow(title: "No padding on the built-in display",
                              isOn: $doc.config.disablePaddingOnBuiltinDisplay)
                    SwitchRow(title: "Tile over the menu bar",
                              isOn: $doc.config.ignoreMenuBar)
                }
            }
        }
    }
}

/// The main display, scaled down, with windows placed exactly as the tiler would place them. They
/// spring to their new places as gaps and padding change.
private struct GapsPreview: View {
    let config: Config
    let layout: Layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Desktop backdrop shared with the animation preview.
    static let wallpaper = LinearGradient(colors: [Color(red: 88 / 255, green: 86 / 255, blue: 214 / 255).opacity(0.55),
                                                   Color(red: 48 / 255, green: 176 / 255, blue: 199 / 255).opacity(0.45)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let full = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let menuBar = (screen.map { $0.frame.maxY - $0.visibleFrame.maxY }) ?? 24
        let dock = (screen.map { $0.visibleFrame.minY - $0.frame.minY }) ?? 0
        GeometryReader { g in
            let scale = min(g.size.width / full.width, g.size.height / full.height)
            let w = full.width * scale, h = full.height * scale
            let bar = config.ignoreMenuBar ? 0 : menuBar * scale
            let frames = windows(in: CGRect(x: 0, y: bar, width: w, height: h - bar - dock * scale), scale: scale)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.wallpaper)
                Rectangle().fill(.black.opacity(0.25)).frame(width: w, height: menuBar * scale)
                    .opacity(config.ignoreMenuBar ? 0 : 1)
                ForEach(Array(frames.enumerated()), id: \.offset) { i, f in
                    MiniWindow(main: i == 0, corner: 4, chrome: f.width > 30)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(width: g.size.width, height: g.size.height)
            .animation(Motion.snap(reduceMotion), value: frames)
            .animation(.easeOut(duration: 0.2), value: config.ignoreMenuBar)
        }
        .accessibilityHidden(true)
    }

    private func windows(in area: CGRect, scale: CGFloat) -> [CGRect] {
        let usable = CGRect(x: area.minX + config.paddingLeft * scale, y: area.minY + config.paddingTop * scale,
                            width: area.width - (config.paddingLeft + config.paddingRight) * scale,
                            height: area.height - (config.paddingTop + config.paddingBottom) * scale)
        let count = 3
        let gap = (config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0) * scale
        guard usable.width > 4, usable.height > 4,
              let frames = layout.frames(count: count, in: usable.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)
        else { return [] }
        return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
    }
}

// MARK: - Behavior

private struct BehaviorPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        PaneScroll {
            Block("Startup") {
                Card {
                    SwitchRow(title: "Open Ouch at login",
                              isOn: Binding(get: { ui.status.launchAtLogin || ui.status.loginNeedsApproval }, set: { on in
                                  LoginItem.set(on)
                                  ui.refreshStatus()
                              }))
                    if ui.status.loginNeedsApproval { LoginApprovalRow() }
                }
            }
            Block("Workspaces") {
                Card {
                    SwitchRow(title: "Use Ouch workspaces",
                              detail: "Per-display workspaces instead of macOS Spaces",
                              isOn: $doc.config.virtualWorkspaces)
                    if doc.config.virtualWorkspaces {
                        SwitchRow(title: "Stay on this workspace when closing a window",
                                  isOn: $doc.config.stayOnWorkspaceAfterClose)
                        Row {
                            TitleDetail(title: "Home Desktop",
                                        detail: WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Ouch starts"
                                            : "Workspaces live on \(WindowManager.shared.homeSpaceSummary). Other Desktops tile normally.")
                        } control: {
                            Button("Use This Desktop") { WindowManager.shared.makeCurrentSpaceHome() }
                        }
                    }
                }
            }
            Block("Focus") {
                Card {
                    SwitchRow(title: "Focus follows mouse",
                              isOn: $doc.config.focusFollowsMouse)
                    SwitchRow(title: "Mouse follows focus",
                              isOn: $doc.config.mouseFollowsFocus)
                }
            }
            Block("Mouse") {
                Card {
                    SwitchRow(title: "Drag to swap",
                              isOn: $doc.config.mouseSwapsWindows)
                    SwitchRow(title: "Resize to adjust the main pane",
                              isOn: $doc.config.mouseResizesWindows)
                    SwitchRow(title: "Drag windows from anywhere",
                              detail: "Hold ⌃⌘ and drag. Restart open apps to apply.",
                              isOn: Binding(get: { ui.dragAnywhere }, set: { on in
                                  DragAnywhere.set(on)
                                  ui.dragAnywhere = DragAnywhere.isEnabled
                              }))
                }
            }
            Block("Windows") {
                Card {
                    SwitchRow(title: "New windows become main",
                              isOn: $doc.config.newWindowsToMain)
                    Row("Main pane resize step", vertical: 8) {
                        let step = Binding(get: { Int((doc.config.windowResizeStep * 100).rounded()) },
                                           set: { doc.config.windowResizeStep = CGFloat($0) / 100 })
                        HStack(spacing: 8) {
                            Text("\(step.wrappedValue)%").monospacedDigit()
                            Stepper("Main pane resize step", value: step, in: 1...25).labelsHidden().controlSize(.small)
                        }
                    }
                }
            }
            Block("Layout HUD") {
                Card {
                    SwitchRow(title: "Show layout name on change",
                              isOn: $doc.config.enablesLayoutHUD)
                    SwitchRow(title: "Also when switching spaces", isOn: $doc.config.enablesLayoutHUDOnSpaceChange)
                        .disabled(!doc.config.enablesLayoutHUD)
                }
            }
        }
    }
}

// MARK: - Floating

private struct FloatingPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var runningApps: [(name: String, id: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.processIdentifier != getpid() }
            .map { ($0.localizedName ?? $0.bundleIdentifier!, $0.bundleIdentifier!, $0.icon) }
            .filter { app in !doc.config.floating.contains(app.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        PaneScroll {
            Block() {
                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Text("Apps in the list below")
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 6) {
                            radio("Always float", true)
                            radio("Are the only ones tiled", false)
                        }
                    }
                    .padding(.vertical, 10)
                    SwitchRow(title: "Float small windows",
                              isOn: $doc.config.floatSmallWindows)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Apps").font(Theme.body(13, .semibold)).foregroundStyle(.primary.opacity(0.85))
                    Spacer()
                    Menu {
                        ForEach(runningApps, id: \.id) { app in
                            Button { if !doc.config.floating.contains(app.id) { withAnimation(.snappy) { doc.config.floating.append(app.id) } } } label: {
                                if let icon = app.icon { Image(nsImage: resized(icon)) }
                                Text(app.name)
                            }
                        }
                    } label: {
                        Label("Add Running App", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize()
                }
                .padding(.horizontal, 2).padding(.bottom, 6)
                Card {
                    if doc.config.floating.isEmpty {
                        Text("No apps yet. Add one from the menu above.").foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                    ForEach(doc.config.floating, id: \.self) { id in
                        HStack(spacing: 10) {
                            appIcon(id)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(id) ?? id)
                                if appName(id) != nil { Text(id).font(Theme.body(11)).foregroundStyle(Theme.secondary) }
                            }
                            Spacer(minLength: 0)
                            RemoveButton(help: "Remove") { withAnimation(.snappy) { doc.config.floating.removeAll { $0 == id } } }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            Block("Add by bundle ID") {
                Card(padding: 9) {
                    HStack(spacing: 8) {
                        TextField("", text: $ui.newID, prompt: Text("com.example.app or com.adobe.*"))
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(add)
                        Button("Add", action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func radio(_ label: String, _ value: Bool) -> some View {
        let on = doc.config.floatingIsBlacklist == value
        return Button { doc.config.floatingIsBlacklist = value } label: {
            HStack(spacing: 7) {
                Circle().fill(on ? Color.accentColor : Theme.control)
                    .overlay(Circle().strokeBorder(Color.black.opacity(on ? 0 : 0.3), lineWidth: 0.5))
                    .overlay(Circle().fill(on ? Color.white : .clear).frame(width: 6, height: 6))
                    .shadow(color: .black.opacity(on ? 0 : 0.12), radius: 0.5, y: 0.5)
                    .frame(width: 14, height: 14)
                Text(label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(.snappy) { doc.config.floating.append(id) }
        ui.newID = ""
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
    private func appURL(_ id: String) -> URL? {
        id.hasSuffix("*") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }
    private func appName(_ id: String) -> String? {
        appURL(id).map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    }
    @ViewBuilder private func appIcon(_ id: String) -> some View {
        if let url = appURL(id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 26, height: 26)
        } else {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26)
        }
    }
}

// MARK: - Animation

private struct AnimationPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private static let presets: [(name: String, seconds: Double)] = [("Snappy", 0.12), ("Smooth", 0.2), ("Relaxed", 0.35)]

    var body: some View {
        let c = doc.config
        let preset = Self.presets.first { abs($0.seconds - c.animationDuration) < 0.005 }?.name
        PaneScroll {
            Card {
                SwitchRow(title: "Animate windows", isOn: $doc.config.animate)
                Row("Speed", vertical: 8) {
                    Segmented(title: "Speed", options: Self.presets.map { ($0.name, $0.name) } + (preset == nil ? [("Custom", "Custom")] : []),
                              selection: Binding(get: { preset ?? "Custom" }, set: { name in
                                  guard let p = Self.presets.first(where: { $0.name == name }) else { return }
                                  doc.config.animationDuration = p.seconds
                                  play() // feel the new speed right away
                              }))
                }
                .dimmed(!c.animate)
                Row("Duration", vertical: 8) {
                    HStack(spacing: 10) {
                        Slider(value: Binding(get: { c.animationDuration }, set: { doc.config.animationDuration = ($0 * 100).rounded() / 100 }),
                               in: 0.05...0.6)
                            .controlSize(.small)
                            .frame(width: 200)
                            .accessibilityLabel("Duration")
                        Text("\(Int((c.animationDuration * 1000).rounded())) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .dimmed(!c.animate)
            }
            Block("Preview") {
                Card(padding: 14) {
                    VStack(spacing: 12) {
                        GeometryReader { geo in
                            let w = geo.size.width, h = geo.size.height, flipped = ui.previewFlipped
                            let seam = flipped ? w * 0.65 - 2 : w * 0.6 - 2
                            ZStack(alignment: .topLeading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(GapsPreview.wallpaper)
                                MiniWindow(main: true, corner: 5, chrome: true)
                                    .frame(width: (flipped ? w * 0.35 : w * 0.6) - 12, height: h - 16)
                                    .offset(x: flipped ? w * 0.65 + 4 : 8, y: 8)
                                MiniWindow(main: false, corner: 5, chrome: true)
                                    .frame(width: (flipped ? w * 0.65 : w * 0.4) - 12, height: h - 16)
                                    .offset(x: flipped ? 8 : w * 0.6 + 4, y: 8)
                                // The windows meet at the seam when they land.
                                ImpactBurst(trigger: flipped, angle: -90, size: 26, delay: c.animate ? c.animationDuration * 0.8 : 0)
                                    .offset(x: seam - 13, y: -4)
                                    .animation(nil, value: flipped)
                            }
                            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                        }
                        .frame(height: 140)
                        .accessibilityHidden(true)
                        Button(action: play) {
                            Label("Play", systemImage: "play.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func play() {
        let c = doc.config
        // The same ease-out cubic curve the real animator uses.
        withAnimation(c.animate ? .timingCurve(0.33, 1, 0.68, 1, duration: c.animationDuration) : nil) {
            ui.previewFlipped.toggle()
        }
    }
}

// MARK: - Keyboard shortcuts

private struct KeybindsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private func category(_ r: BindRow) -> ActionCategory {
        Actions.match(r)?.category ?? Actions.rangeSummary(r)?.category ?? .custom
    }

    private func matches(_ r: BindRow) -> Bool {
        guard r.submap == ui.bindMode else { return false }
        guard !ui.search.isEmpty else { return true }
        let q = ui.search.lowercased()
        let title = doc.title(r)
        return [title, r.dispatcher, r.args, r.key, doc.prettyShortcut(r).joined()].contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        let sections = ActionCategory.allCases.map { cat in (cat, doc.binds.filter { category($0) == cat && matches($0) }) }
            .filter { !$0.1.isEmpty }
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Segmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") }, selection: $ui.bindMode)
                    .help("Global shortcuts work everywhere. Mode shortcuts need the mode on, so single keys are fine there.")
                Spacer()
                Menu {
                    ForEach(Actions.byCategory, id: \.0) { cat, actions in
                        Menu {
                            ForEach(actions) { a in Button(a.title) { add(a.dispatcher, a.args) } }
                        } label: { Label(cat.rawValue, systemImage: cat.symbol) }
                    }
                    Menu {
                        Button("Switch to Spaces 1–10  (keys 1…0)") { add("workspace", "1..10", key: "1..0") }
                        Button("Move Window to Spaces 1–10  (keys 1…0)") { add("movetoworkspace", "1..10", key: "1..0") }
                        Button("Focus with H J K L") { add("movefocus", "l|d|u|r", key: "h|j|k|l") }
                        Button("Move Window with H J K L") { add("movewindow", "l|d|u|r", key: "h|j|k|l") }
                        Divider()
                        Button("Custom Range…") { add("workspace", "1..5", key: "1..5") }
                    } label: { Label("Ranges", systemImage: "ellipsis.rectangle") }
                    Divider()
                    Button("Custom Dispatcher…") { add("layoutmsg", "") } // matches no preset, so the raw editor shows
                } label: {
                    Label("Add Shortcut", systemImage: "plus")
                }
                .fixedSize()
            }
            .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 12)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.0) { cat, rows in
                            Text(cat.rawValue).font(Theme.body(11, .semibold)).foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 2).padding(.top, 14).padding(.bottom, 6)
                            ForEach(rows) { row in
                                BindRowView(doc: doc, ui: ui, rowID: row.id)
                                    .padding(.vertical, 5)
                                    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
                                    .id(row.id)
                            }
                        }
                        if sections.isEmpty {
                            Text(ui.search.isEmpty ? "No shortcuts yet" : "No shortcuts match “\(ui.search)”")
                                .foregroundStyle(Theme.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 24)
                }
                .onChange(of: ui.recording) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
        .searchable(text: $ui.search, placement: .toolbar, prompt: "Search shortcuts")
        .onDisappear { ui.recording = nil }
    }

    private func add(_ dispatcher: String, _ args: String, key: String = "") {
        let row = BindRow(mods: ui.bindMode.isEmpty ? doc.modVarName : "", key: key, dispatcher: dispatcher, args: args,
                          submap: ui.bindMode)
        doc.binds.append(row)
        ui.search = ""
        DispatchQueue.main.async { ui.recording = row.id }
    }
}

private struct BindRowView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let rowID: UUID

    private var index: Int? { doc.binds.firstIndex { $0.id == rowID } }

    private func dispatcherOptions(_ current: String) -> [(value: String, label: String)] {
        Actions.dispatchers.map { ($0, $0) } + (Actions.dispatchers.contains(current) ? [] : [(current, current)])
    }

    var body: some View {
        if let i = index {
            let row = doc.binds[i]
            let action = Actions.match(row)
            let issue = doc.issue(row)
            let isRange = BindRange.isRange(row.key)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    recorder(row)
                    if isRange {
                        HStack(spacing: 8) {
                            PopUp(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher, bordered: true)
                                .frame(width: 140, alignment: .leading)
                            TextField("Keys", text: $doc.binds[i].key, prompt: Text("1..0"))
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12, .regular))
                                .frame(width: 90)
                            Image(systemName: "arrow.right").foregroundStyle(Theme.secondary)
                            TextField("Values", text: $doc.binds[i].args, prompt: Text("1..10"))
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12, .regular))
                        }
                    } else {
                        actionMenu(i, action)
                        if row.dispatcher == "exec" {
                            TextField("", text: $doc.binds[i].args, prompt: Text("open -na Terminal"))
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12, .regular))
                        } else if action == nil {
                            PopUp(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher, bordered: true)
                                .frame(width: 140, alignment: .leading)
                            TextField("", text: $doc.binds[i].args, prompt: Text("arguments"))
                                .textFieldStyle(.roundedBorder).font(Theme.mono(12, .regular))
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    if let issue {
                        Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? .red : .orange)
                            .help(issue.message)
                    }
                    RemoveButton(help: "Delete shortcut") { withAnimation(.snappy) { doc.binds.removeAll { $0.id == rowID } } }
                }
                if isRange, issue == nil {
                    Text(rangePreview(row)).font(Theme.body(11)).foregroundStyle(Theme.secondary)
                        .padding(.leading, 4).padding(.top, 4).padding(.bottom, 1)
                }
                if let issue, issue.severity == .error {
                    Text(issue.message).font(Theme.body(11)).foregroundStyle(.red).padding(.leading, 4).padding(.top, 4)
                }
            }
        }
    }

    /// "Switch to Space 1…10:  ⌥1 → 1 · ⌥2 → 2 · … · ⌥0 → 10"
    private func rangePreview(_ row: BindRow) -> String {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return "" }
        let mods = doc.prettyShortcut(BindRow(mods: row.mods, key: "", dispatcher: "", args: "")).dropLast().joined()
        func one(_ p: (key: String, arg: String)) -> String {
            let key = doc.prettyShortcut(BindRow(mods: "", key: p.key, dispatcher: "", args: "")).last ?? p.key
            return "\(mods)\(key) → \(p.arg.isEmpty ? row.dispatcher : p.arg)"
        }
        let shown = pairs.count > 5 ? pairs.prefix(3).map(one) + ["…", one(pairs.last!)] : pairs.map(one)
        return "\(doc.title(row)):  " + shown.joined(separator: "  ·  ")
    }

    private func recorder(_ row: BindRow) -> some View {
        let recording = ui.recording == rowID
        return Button {
            ui.recording = recording ? nil : rowID
        } label: {
            Group {
                if recording {
                    Text(BindRange.isRange(row.key) ? "Modifiers + key · Esc cancels"
                         : row.submap.isEmpty ? "Press keys… (Esc cancels)" : "Press keys… (click to cancel)")
                        .font(Theme.body(11)).foregroundStyle(Color.accentColor)
                        .lineLimit(1).minimumScaleFactor(0.8)
                } else if row.key.isEmpty {
                    Text("Click to record").font(Theme.body(11)).foregroundStyle(Theme.secondary)
                } else {
                    // Freshly recorded keys drop in with a little bump.
                    Keycaps(caps: doc.prettyShortcut(row))
                        .squish(on: row.mods + row.key, anchor: .center)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: 150, alignment: .leading)
            .frame(minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Color.accentColor.opacity(0.14) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? Color.accentColor : Color.gray.opacity(0.25),
                                                                   style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionMenu(_ i: Int, _ action: Action?) -> some View {
        Menu {
            ForEach(Actions.byCategory, id: \.0) { cat, actions in
                Menu {
                    ForEach(actions) { a in
                        Button(a.title) {
                            doc.binds[i].dispatcher = a.dispatcher
                            if a.dispatcher != "exec" || doc.binds[i].args.isEmpty || action?.dispatcher != "exec" {
                                doc.binds[i].args = a.args
                            }
                        }
                    }
                } label: { Label(cat.rawValue, systemImage: cat.symbol) }
            }
        } label: {
            Text(action?.title ?? "Custom")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @ObservedObject var doc: ConfigDocument

    private var binaryPath: String { Bundle.main.executablePath ?? "ouch" }

    var body: some View {
        PaneScroll {
            Block("Files") {
                Card {
                    Row {
                        path("Config file", Config.url)
                    } control: {
                        HStack(spacing: 8) {
                            Button("Edit in TextEdit") {
                                NSWorkspace.shared.open([Config.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                                        configuration: NSWorkspace.OpenConfiguration())
                            }
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) }
                        }
                    }
                    Row {
                        path("Log file", Log.url)
                    } control: {
                        Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                    }
                    SwitchRow(title: "Detailed logging",
                              isOn: $doc.config.debugLogging)
                }
            }
            Block("Command line") {
                Card(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Control Ouch from a terminal, like hyprctl:")
                        Text("\(binaryPath) dispatch movefocus l\n\(binaryPath) dump\n\(binaryPath) reload")
                            .font(Theme.mono(11))
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        Text("dump writes the current layout state to the log. exec is only allowed from keyboard shortcuts.")
                            .font(Theme.body(11)).foregroundStyle(Theme.secondary)
                    }
                }
            }
            Block("Backups") {
                Card {
                    Row {
                        TitleDetail(title: "Keyboard shortcuts", detail: "Saves a dated copy next to the config file")
                    } control: {
                        Button("Back Up Now") {
                            if let url = doc.backUpShortcuts() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                }
            }
            Block("Reset") {
                Card {
                    Row("Keyboard shortcuts", vertical: 8) {
                        Button("Restore Defaults…") {
                            if confirm("Restore the default keyboard shortcuts?", "Your own shortcuts will be replaced.") {
                                doc.restoreDefaultShortcuts()
                            }
                        }
                    }
                    Row("Everything", vertical: 8) {
                        Button("Reset All Settings…") {
                            if confirm("Reset all settings to their defaults?", "Layouts, gaps, floating apps and shortcuts are all reset. Your main modifier is kept.") {
                                doc.resetEverything()
                            }
                        }
                    }
                }
            }
        }
    }

    private func path(_ title: String, _ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(Theme.mono(11, .regular)).foregroundStyle(Theme.secondary).textSelection(.enabled)
        }
    }

    private func confirm(_ title: String, _ detail: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = detail
        a.addButton(withTitle: "Reset")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        return a.runModal() == .alertFirstButtonReturn
    }
}
