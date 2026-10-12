import AppKit
import SwiftUI

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    let doc = ConfigDocument()
    private(set) lazy var ui = SettingsUI(doc: doc)

    func show(pane: Pane?) {
        let wasVisible = window?.isVisible ?? false
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "Hyprthyst Settings"
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 820, height: 520)
            w.toolbarStyle = .unified
            w.contentView = NSHostingView(rootView: SettingsView(doc: doc, ui: ui))
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("HyprthystSettings")
            window = w
        }
        if let pane { ui.pane = pane }
        if !wasVisible {
            doc.beginSession()
            ui.beginSession()
        }
        // Show in the Dock and ⌘-Tab while settings are open, like other menu bar apps do.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

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
        case .behavior: "cursorarrow.click.2"
        case .floating: "macwindow.on.rectangle"
        case .animation: "wand.and.stars"
        case .keybinds: "command"
        case .advanced: "wrench.and.screwdriver.fill"
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
    var subtitle: String {
        switch self {
        case .overview: "Status and quick settings"
        case .layouts: "Choose the layouts you cycle through"
        case .gaps: "Space between windows and around the screen"
        case .behavior: "Startup, focus, mouse and new windows"
        case .floating: "Apps and windows that are never tiled"
        case .animation: "How windows move into place"
        case .keybinds: "Hyprland-style keybinds"
        case .advanced: "Files, logging and resets"
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
        if e.keyCode == 53 && flags.isEmpty && doc.binds[i].submap.isEmpty { // Esc cancels (global rows)
            recording = nil
            return nil
        }
        guard let name = ConfigDocument.keyName(for: e.keyCode) else { NSSound.beep(); return nil }
        if doc.binds[i].submap.isEmpty == false, flags.isEmpty, e.keyCode == 53 {
            // Esc inside a mode row is a legit key to bind (e.g. to leave the mode).
            doc.binds[i].key = "escape"; doc.binds[i].mods = ""
        } else if BindRange.isRange(doc.binds[i].key) {
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
        NavigationSplitView {
            List(Pane.allCases, selection: $ui.pane) { p in
                HStack(spacing: 10) {
                    IconTile(symbol: p.icon, color: p.color, size: 24)
                    Text(p.rawValue)
                    Spacer()
                    if p == .overview && !(ui.status.trusted && ui.status.keybindsActive) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    } else if p == .keybinds && doc.problemCount > 0 {
                        Text("\(doc.problemCount)").font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                    }
                }
                .padding(.vertical, 2)
                .tag(p)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 220)
        } detail: {
            let pane = ui.pane ?? .overview
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
            .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(doc: doc) }
            .navigationTitle(pane.rawValue)
            .navigationSubtitle(pane.subtitle)
        }
    }
}

private struct StatusBar: View {
    @ObservedObject var doc: ConfigDocument

    var body: some View {
        HStack(spacing: 10) {
            if let err = doc.saveError {
                Label("Couldn't save: \(err)", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            } else if doc.problemCount > 0 {
                Label("Fix \(doc.problemCount) shortcut\(doc.problemCount == 1 ? "" : "s") to save your changes",
                      systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if doc.isDirty {
                Label("Saving…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            } else if !doc.fileErrors.isEmpty {
                Label("\(doc.fileErrors.count) line\(doc.fileErrors.count == 1 ? "" : "s") in the config file were skipped",
                      systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    .help(doc.fileErrors.joined(separator: "\n"))
            } else {
                Label("Changes apply instantly", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Spacer()
            if doc.hasChangesSinceOpen {
                Button("Undo All Changes") { doc.undoAllChanges() }
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Shared components

private struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
    }
}

/// Toggle with a secondary explanation line.
private struct DetailToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NumberRow: View {
    let title: String
    @Binding var value: CGFloat
    var range: ClosedRange<CGFloat> = 0...60

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: $value, in: range, step: 1).frame(minWidth: 160)
                TextField("", value: Binding(get: { Double(value) }, set: { value = CGFloat(min(200, max(0, $0))) }), format: .number)
                    .frame(width: 44)
                    .multilineTextAlignment(.trailing)
                Text("px").foregroundStyle(.secondary)
            }
        }
    }
}

private struct Keycaps: View {
    let caps: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(caps.enumerated()), id: \.offset) { _, c in
                Text(c)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, c.count > 1 ? 5 : 0)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.35)))
                    .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
            }
        }
    }
}

/// Miniature of a layout, drawn with the real layout code.
private struct LayoutThumbnail: View {
    let layout: Layout
    var count = 4
    var selected = false

    var body: some View {
        Canvas { ctx, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5)
            ctx.fill(bg, with: .color(.secondary.opacity(0.13)))
            let pad = max(2, size.width * 0.03)
            let r = CGRect(origin: .zero, size: size).insetBy(dx: pad, dy: pad)
            let gap = pad
            let frames = layout.frames(count: count, in: r.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)?
                .map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
                ?? [CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.1, width: r.width * 0.55, height: r.height * 0.55),
                    CGRect(x: r.minX + r.width * 0.38, y: r.minY + r.height * 0.35, width: r.width * 0.55, height: r.height * 0.55)]
            let tint = selected ? Color.accentColor : Color.secondary
            for (i, f) in frames.enumerated().reversed() {
                let p = Path(roundedRect: f, cornerRadius: 2.5)
                ctx.fill(p, with: .color(tint.opacity(i == 0 ? 0.9 : 0.45)))
                if layout == .fullscreen || layout == .floating || layout == .twoPane || layout == .twoPaneRight {
                    ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 0.75)
                }
            }
        }
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
        Form {
            Section { hero(s) }

            if s.trusted && !s.screens.isEmpty {
                Section {
                    ForEach(s.screens, id: \.uuid) { screen in
                        HStack(spacing: 12) {
                            LayoutThumbnail(layout: screen.layout, selected: true).frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(screen.workspace.isEmpty ? screen.name : "\(screen.name) · Workspace \(screen.workspace)")
                                Text(screen.layout.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Picker("", selection: Binding(get: { screen.layout }, set: { l in
                                WindowManager.shared.setLayout(l, screen: screen.uuid)
                                ui.refreshStatus()
                            })) {
                                ForEach(Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                } header: {
                    Text("Displays")
                } footer: {
                    Text("Applies to the workspace on that display. Each workspace remembers its own layout.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Quick settings") {
                Toggle("Open at login", isOn: Binding(get: { ui.status.launchAtLogin || ui.status.loginNeedsApproval }, set: { on in
                    LoginItem.set(on)
                    ui.refreshStatus()
                }))
                if ui.status.loginNeedsApproval {
                    HStack {
                        Label("macOS is waiting for you to allow Hyprthyst in Login Items", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange).font(.callout)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSettings() }
                    }
                }
                Toggle("Tiling", isOn: Binding(get: { ui.status.tilingEnabled }, set: { _ in
                    WindowManager.shared.toggleTiling()
                    ui.refreshStatus()
                }))
                .disabled(!s.running)
                Toggle("Focus follows mouse", isOn: $doc.config.focusFollowsMouse)
                Toggle("Mouse follows focus", isOn: $doc.config.mouseFollowsFocus)
                Toggle("Animate windows", isOn: $doc.config.animate)
                Picker("Main modifier", selection: Binding(get: { doc.modValue }, set: { doc.modValue = $0 })) {
                    ForEach(ConfigDocument.modifierChoices, id: \.value) { Text($0.label).tag($0.value) }
                    if !ConfigDocument.modifierChoices.contains(where: { $0.value == doc.modValue }) {
                        Text(doc.modValue).tag(doc.modValue)
                    }
                }
            }

            Section("Updates") {
                if updater.isConfigured {
                    Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                    Toggle("Download updates automatically", isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                        .disabled(!updater.automaticallyChecks)
                    Toggle("Include beta releases", isOn: Binding(get: { updater.receivesBeta }, set: { updater.receivesBeta = $0 }))
                    LabeledContent(updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" } ?? "Not checked yet") {
                        Button("Check Now") { updater.checkForUpdates() }
                    }
                } else {
                    Text("This build has no update feed. Release builds published with Amore update themselves.")
                        .foregroundStyle(.secondary)
                }
            }

            Section { AmoreCredit().frame(maxWidth: .infinity) }
                .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func hero(_ s: WindowManager.Status) -> some View {
        if !s.trusted {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    IconTile(symbol: "lock.fill", color: .orange, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Hyprthyst needs Accessibility access").font(.title3.weight(.semibold))
                        Text("macOS only lets apps move other apps' windows with this permission.")
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    step(1, "Click Open Accessibility Settings. A guide appears next to System Settings.")
                    step(2, "Turn on Hyprthyst in the list.")
                    step(3, "Already on but still not working? Rebuilding the app invalidates the old entry. Click Reset Permission, then turn it on again.")
                }
                .font(.callout)
                HStack {
                    Button("Open Accessibility Settings") { Permissions.openSettings() }
                        .buttonStyle(.borderedProminent)
                    Button("Reset Permission") { Permissions.reset() }
                    Spacer()
                    ProgressView().controlSize(.small)
                    Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 14) {
                IconTile(symbol: s.keybindsActive ? "checkmark" : "keyboard.badge.exclamationmark",
                         color: s.keybindsActive ? .green : .orange, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(!s.tilingEnabled ? "Tiling is paused" : s.keybindsActive ? "Hyprthyst is running" : "Keyboard shortcuts aren't active")
                        .font(.title3.weight(.semibold))
                    Text(summary(s)).foregroundStyle(.secondary)
                }
                Spacer()
                if !s.keybindsActive {
                    Button("Retry") { Hotkeys.shared.restart(); ui.refreshStatus() }
                }
            }
            .padding(.vertical, 6)
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
            Text("\(n)").font(.caption.bold()).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            Text(text).fixedSize(horizontal: false, vertical: true)
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
                    .scaleEffect(hovering ? 1.35 : 1)
                    .rotationEffect(.degrees(hovering ? -12 : 0))
                    .offset(y: hovering ? -2 : 0)
                    .shadow(color: .pink.opacity(hovering ? 0.7 : 0), radius: 4)
                Text("Amore").fontWeight(.semibold)
            }
            .font(.caption2)
            .foregroundStyle(hovering ? .primary : .tertiary)
            .animation(.spring(response: 0.3, dampingFraction: 0.45), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .help("Updates delivered by Amore")
    }
}

enum Permissions {
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        PermissionGuide.shared.show()
    }

    /// Drops any Accessibility entry left by an older build or moved copy; it would show as
    /// "on" in System Settings while macOS rejects this binary.
    static func clearStaleEntry() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "local.hyprthyst"]
        try? p.run()
        p.waitUntilExit()
    }

    /// Starts the grant flow from a clean slate: clear stale entry, prompt, open Settings + guide.
    static func request() {
        guard !AXIsProcessTrusted() else { return }
        clearStaleEntry()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openSettings()
    }

    static func reset() {
        clearStaleEntry()
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        openSettings()
    }

    /// Closes the System Settings window (needs Accessibility, which we have by now).
    static func closeSettingsWindows() {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &button) == .success, let button {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }
    }
}

// MARK: - Layouts

private struct LayoutsPane: View {
    @ObservedObject var doc: ConfigDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cycle order").font(.headline)
                    Text("Next Layout steps through these from left to right. New spaces start with the first one.")
                        .font(.callout).foregroundStyle(.secondary)
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
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.07)))

                VStack(alignment: .leading, spacing: 10) {
                    Text("All layouts").font(.headline)
                    Text("Click a layout to add it to the cycle or take it out.").font(.callout).foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                        ForEach(Layout.allCases, id: \.self) { card($0) }
                    }
                }
            }
            .padding(20)
        }
    }

    private func orderChip(_ i: Int, _ l: Layout) -> some View {
        VStack(spacing: 6) {
            LayoutThumbnail(layout: l, selected: true).frame(width: 84, height: 52)
            Text("\(i + 1). \(l.title)").font(.caption.weight(.medium)).lineLimit(1)
            HStack(spacing: 2) {
                Button { doc.config.layouts.swapAt(i, i - 1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 16) }
                    .disabled(i == 0)
                    .help("Move earlier")
                Button { doc.config.layouts.swapAt(i, i + 1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 16) }
                    .disabled(i == doc.config.layouts.count - 1)
                    .help("Move later")
            }
            .buttonStyle(.borderless)
        }
        .frame(width: 104)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private func card(_ l: Layout) -> some View {
        let index = doc.config.layouts.firstIndex(of: l)
        let on = index != nil
        let locked = on && doc.config.layouts.count == 1
        return Button {
            if let index { if !locked { doc.config.layouts.remove(at: index) } } else { doc.config.layouts.append(l) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                LayoutThumbnail(layout: l, selected: on)
                    .frame(height: 86)
                    .overlay(alignment: .topTrailing) {
                        if let index {
                            Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor))
                                .padding(5)
                        }
                    }
                Text(l.title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                Text(l.blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2, reservesSpace: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: on ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(locked ? "At least one layout has to stay in the cycle" : on ? "Remove from the cycle" : "Add to the cycle")
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
        Form {
            Section {
                GapsPreview(config: c, layout: c.layouts.first { ![.floating, .fullscreen].contains($0) } ?? .tall)
                    .frame(height: 230)
                    .padding(.vertical, 4)
            }
            Section("Between windows") {
                Toggle("Gaps between windows", isOn: $doc.config.windowMargins)
                NumberRow(title: "Gap", value: $doc.config.windowMarginSize).disabled(!c.windowMargins)
                DetailToggle(title: "Smart gaps", detail: "No gap when a screen has only one window",
                             isOn: $doc.config.smartWindowMargins)
                    .disabled(!c.windowMargins)
            }
            Section("Screen edges") {
                Toggle("Same padding on every side", isOn: Binding(get: { ui.linkedPadding }, set: { on in
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
                DetailToggle(title: "No padding on the built-in display",
                             detail: "Useful on a small laptop screen when you also use an external display",
                             isOn: $doc.config.disablePaddingOnBuiltinDisplay)
                DetailToggle(title: "Tile over the menu bar", detail: "For setups where the menu bar auto-hides",
                             isOn: $doc.config.ignoreMenuBar)
            }
        }
        .formStyle(.grouped)
    }
}

/// The main display, scaled down, with windows placed exactly as the tiler would place them.
private struct GapsPreview: View {
    let config: Config
    let layout: Layout

    var body: some View {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let full = screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let menuBar = (screen.map { $0.frame.maxY - $0.visibleFrame.maxY }) ?? 24
        let dock = (screen.map { $0.visibleFrame.minY - $0.frame.minY }) ?? 0
        Canvas { ctx, size in
            let scale = min(size.width / full.width, size.height / full.height)
            let w = full.width * scale, h = full.height * scale
            let origin = CGPoint(x: (size.width - w) / 2, y: (size.height - h) / 2)
            let screenRect = CGRect(origin: origin, size: CGSize(width: w, height: h))
            ctx.fill(Path(roundedRect: screenRect, cornerRadius: 8),
                     with: .linearGradient(Gradient(colors: [.indigo.opacity(0.55), .teal.opacity(0.45)]),
                                           startPoint: screenRect.origin, endPoint: CGPoint(x: screenRect.maxX, y: screenRect.maxY)))
            let bar = CGRect(x: screenRect.minX, y: screenRect.minY, width: w, height: menuBar * scale)
            if !config.ignoreMenuBar { ctx.fill(Path(bar), with: .color(.black.opacity(0.25))) }

            var usable = CGRect(x: screenRect.minX, y: screenRect.minY + (config.ignoreMenuBar ? 0 : menuBar * scale),
                                width: w, height: h - (config.ignoreMenuBar ? 0 : menuBar * scale) - dock * scale)
            usable = CGRect(x: usable.minX + config.paddingLeft * scale, y: usable.minY + config.paddingTop * scale,
                            width: usable.width - (config.paddingLeft + config.paddingRight) * scale,
                            height: usable.height - (config.paddingTop + config.paddingBottom) * scale)
            let count = 3
            let gap = (config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0) * scale
            guard usable.width > 4, usable.height > 4,
                  let frames = layout.frames(count: count, in: usable.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)
            else { return }
            for (i, f) in frames.enumerated() {
                let r = f.insetBy(dx: gap / 2, dy: gap / 2)
                let p = Path(roundedRect: r, cornerRadius: 4)
                ctx.fill(p, with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.95)))
                ctx.stroke(p, with: .color(i == 0 ? Color.accentColor : .black.opacity(0.2)), lineWidth: i == 0 ? 1.5 : 0.5)
                let title = CGRect(x: r.minX, y: r.minY, width: r.width, height: min(9, r.height))
                ctx.fill(Path(roundedRect: title, cornerRadius: 3), with: .color(.secondary.opacity(0.18)))
                for (j, col) in [Color.red, .yellow, .green].enumerated() where r.width > 30 {
                    ctx.fill(Path(ellipseIn: CGRect(x: r.minX + 4 + CGFloat(j) * 6, y: r.minY + 2.5, width: 4, height: 4)),
                             with: .color(col.opacity(0.8)))
                }
            }
        }
    }
}

// MARK: - Behavior

private struct BehaviorPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: Binding(get: { ui.status.launchAtLogin || ui.status.loginNeedsApproval }, set: { on in
                    LoginItem.set(on)
                    ui.refreshStatus()
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Hyprthyst at login")
                        Text("Also listed in System Settings → General → Login Items.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if ui.status.loginNeedsApproval {
                    HStack {
                        Label("macOS is waiting for you to allow Hyprthyst in Login Items", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange).font(.callout)
                        Spacer()
                        Button("Open Login Items") { LoginItem.openSettings() }
                    }
                }
            }
            Section("Workspaces") {
                DetailToggle(title: "Use Hyprthyst workspaces",
                             detail: "Instant, per-monitor workspaces like Hyprland, instead of macOS Spaces. Windows on hidden workspaces are parked just off-screen. Works best with a single macOS Space.",
                             isOn: $doc.config.virtualWorkspaces)
                if doc.config.virtualWorkspaces {
                    LabeledContent {
                        Button("Use This Desktop") { WindowManager.shared.makeCurrentSpaceHome() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Home Desktop")
                            Text(WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Hyprthyst starts"
                                 : "Workspaces live on \(WindowManager.shared.homeSpaceSummary). Other Desktops tile normally.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Focus") {
                DetailToggle(title: "Focus follows mouse",
                             detail: "Resting the pointer on a window focuses it. Menus and the Dock are ignored.",
                             isOn: $doc.config.focusFollowsMouse)
                DetailToggle(title: "Mouse follows focus",
                             detail: "Moving focus with the keyboard moves the pointer to the window's center.",
                             isOn: $doc.config.mouseFollowsFocus)
            }
            Section("Mouse") {
                DetailToggle(title: "Drag to swap", detail: "Drop a window onto another to swap them, or onto another display to move it there.",
                             isOn: $doc.config.mouseSwapsWindows)
                DetailToggle(title: "Resize to adjust the main pane", detail: "Dragging the edge between panes changes how much room the main pane gets.",
                             isOn: $doc.config.mouseResizesWindows)
            }
            Section("Windows") {
                DetailToggle(title: "New windows become main", detail: "Otherwise they're added at the end.",
                             isOn: $doc.config.newWindowsToMain)
                LabeledContent("Main pane resize step") {
                    Stepper(value: Binding(get: { Int((doc.config.windowResizeStep * 100).rounded()) },
                                           set: { doc.config.windowResizeStep = CGFloat($0) / 100 }), in: 1...25) {
                        Text("\(Int((doc.config.windowResizeStep * 100).rounded()))%").monospacedDigit()
                    }
                }
            }
            Section("Layout HUD") {
                DetailToggle(title: "Show layout name on change", detail: "A short overlay in the middle of the screen.",
                             isOn: $doc.config.enablesLayoutHUD)
                Toggle("Also when switching spaces", isOn: $doc.config.enablesLayoutHUDOnSpaceChange)
                    .disabled(!doc.config.enablesLayoutHUD)
            }
        }
        .formStyle(.grouped)
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
        Form {
            Section {
                Picker("Apps in the list below", selection: $doc.config.floatingIsBlacklist) {
                    Text("Always float").tag(true)
                    Text("Are the only ones tiled").tag(false)
                }
                .pickerStyle(.radioGroup)
                DetailToggle(title: "Float small windows", detail: "Windows under 500 × 500 when they open, like preference panes and palettes.",
                             isOn: $doc.config.floatSmallWindows)
            } footer: {
                Text("Dialogs and windows that can't be resized always float. Use Toggle Floating to float any single window.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if doc.config.floating.isEmpty {
                    HStack {
                        Spacer()
                        Text("No apps yet. Add one from the menu below.").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                ForEach(doc.config.floating, id: \.self) { id in
                    HStack(spacing: 10) {
                        appIcon(id)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(appName(id) ?? id)
                            if appName(id) != nil { Text(id).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button { doc.config.floating.removeAll { $0 == id } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Remove")
                    }
                }
            } header: {
                HStack {
                    Text("Apps")
                    Spacer()
                    Menu {
                        ForEach(runningApps, id: \.id) { app in
                            Button { if !doc.config.floating.contains(app.id) { doc.config.floating.append(app.id) } } label: {
                                if let icon = app.icon { Image(nsImage: resized(icon)) }
                                Text(app.name)
                            }
                        }
                    } label: {
                        Label("Add Running App", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            Section("Add by bundle ID") {
                HStack {
                    TextField("", text: $ui.newID, prompt: Text("com.example.app or com.adobe.*"))
                        .labelsHidden()
                        .onSubmit(add)
                    Button("Add", action: add).disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        doc.config.floating.append(id)
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
            Image(systemName: "app.dashed").font(.title2).frame(width: 26, height: 26).foregroundStyle(.secondary)
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
        Form {
            Section {
                Toggle("Animate windows", isOn: $doc.config.animate)
                Picker("Speed", selection: Binding(get: {
                    Self.presets.first { abs($0.seconds - c.animationDuration) < 0.005 }?.name ?? "Custom"
                }, set: { name in
                    if let p = Self.presets.first(where: { $0.name == name }) { doc.config.animationDuration = p.seconds }
                })) {
                    ForEach(Self.presets, id: \.name) { Text($0.name).tag($0.name) }
                    if !Self.presets.contains(where: { abs($0.seconds - c.animationDuration) < 0.005 }) {
                        Text("Custom").tag("Custom")
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!c.animate)
                LabeledContent("Duration") {
                    HStack {
                        Slider(value: $doc.config.animationDuration, in: 0.05...0.6, step: 0.01).frame(minWidth: 180)
                        Text("\(Int((c.animationDuration * 1000).rounded())) ms").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!c.animate)
            }
            Section("Preview") {
                VStack(spacing: 12) {
                    GeometryReader { geo in
                        let w = geo.size.width, h = geo.size.height, flipped = ui.previewFlipped
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [.indigo.opacity(0.5), .teal.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 1.5))
                                .frame(width: (flipped ? w * 0.35 : w * 0.6) - 12, height: h - 16)
                                .offset(x: flipped ? w * 0.65 + 4 : 8, y: 8)
                            RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .windowBackgroundColor).opacity(0.9))
                                .frame(width: (flipped ? w * 0.65 : w * 0.4) - 12, height: h - 16)
                                .offset(x: flipped ? 8 : w * 0.6 + 4, y: 8)
                        }
                    }
                    .frame(height: 140)
                    Button {
                        // The same ease-out cubic curve the real animator uses.
                        withAnimation(c.animate ? .timingCurve(0.33, 1, 0.68, 1, duration: c.animationDuration) : nil) {
                            ui.previewFlipped.toggle()
                        }
                    } label: { Label("Play", systemImage: "play.fill") }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search shortcuts", text: $ui.search).textFieldStyle(.plain)
                    if !ui.search.isEmpty {
                        Button { ui.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.1)))
                .frame(maxWidth: 240)
                Picker("", selection: $ui.bindMode) {
                    ForEach(doc.submaps, id: \.self) { m in
                        Text(m.isEmpty ? "Global" : "\(m.capitalized) mode").tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Global shortcuts work everywhere. Mode shortcuts only work after entering the mode, so single keys are fine there.")
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                List {
                    ForEach(ActionCategory.allCases) { cat in
                        let rows = doc.binds.filter { category($0) == cat && matches($0) }
                        if !rows.isEmpty {
                            Section {
                                ForEach(rows) { row in
                                    BindRowView(doc: doc, ui: ui, rowID: row.id).id(row.id)
                                }
                            } header: {
                                Label(cat.rawValue, systemImage: cat.symbol)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .onChange(of: ui.recording) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
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

    var body: some View {
        if let i = index {
            let row = doc.binds[i]
            let action = Actions.match(row)
            let issue = doc.issue(row)
            let isRange = BindRange.isRange(row.key)
            HStack(spacing: 12) {
                recorder(row)
                    .frame(width: 150, alignment: .leading)
                if isRange {
                    Picker("", selection: $doc.binds[i].dispatcher) {
                        ForEach(Actions.dispatchers, id: \.self) { Text($0).tag($0) }
                        if !Actions.dispatchers.contains(row.dispatcher) { Text(row.dispatcher).tag(row.dispatcher) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    TextField("Keys", text: $doc.binds[i].key, prompt: Text("1..0"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 90)
                        .help("Keys: 1..0 (number row), a..d, f1..f12, or h|j|k|l")
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    TextField("Values", text: $doc.binds[i].args, prompt: Text("1..10"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .help("Values paired with the keys in order: 1..10, l|d|u|r, or one value for all keys")
                } else {
                    actionMenu(i, action)
                        .frame(width: 250, alignment: .leading)
                }
                if isRange {
                    EmptyView()
                } else if row.dispatcher == "exec" {
                    TextField("", text: $doc.binds[i].args, prompt: Text("open -na Terminal"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else if action == nil {
                    Picker("", selection: $doc.binds[i].dispatcher) {
                        ForEach(Actions.dispatchers, id: \.self) { Text($0).tag($0) }
                        if !Actions.dispatchers.contains(row.dispatcher) { Text(row.dispatcher).tag(row.dispatcher) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    TextField("", text: $doc.binds[i].args, prompt: Text("arguments"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                } else {
                    Spacer(minLength: 0)
                }
                if let issue {
                    Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                        .foregroundStyle(issue.severity == .error ? .red : .orange)
                        .help(issue.message)
                }
                Button { doc.binds.removeAll { $0.id == rowID } } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete shortcut")
            }
            .padding(.vertical, 3)
            if isRange, issue == nil {
                Text(rangePreview(row)).font(.caption).foregroundStyle(.secondary).padding(.leading, 4)
            }
            if let issue, issue.severity == .error {
                Text(issue.message).font(.caption).foregroundStyle(.red).padding(.leading, 4)
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
                    Text(BindRange.isRange(row.key) ? "Press modifiers + any key" : "Press keys… (Esc cancels)")
                        .font(.caption).foregroundStyle(Color.accentColor)
                } else if row.key.isEmpty {
                    Text("Click to record").font(.caption).foregroundStyle(.secondary)
                } else {
                    Keycaps(caps: doc.prettyShortcut(row))
                }
            }
            .frame(minWidth: 138, minHeight: 26, alignment: .leading)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(recording ? Color.accentColor.opacity(0.14) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.25),
                                                                   style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
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
            Label(action?.title ?? "Custom", systemImage: action?.symbol ?? "curlybraces")
        }
        .fixedSize()
    }
}

// MARK: - Advanced

private struct AdvancedPane: View {
    @ObservedObject var doc: ConfigDocument

    private var binaryPath: String { Bundle.main.executablePath ?? "Hyprthyst" }

    var body: some View {
        Form {
            Section("Files") {
                LabeledContent {
                    HStack {
                        Button("Edit in TextEdit") {
                            NSWorkspace.shared.open([Config.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                                    configuration: NSWorkspace.OpenConfiguration())
                        }
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Config.url]) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Config file")
                        Text(Config.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                LabeledContent {
                    Button("Open Log") { NSWorkspace.shared.open(Log.url) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Log file")
                        Text(Log.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                DetailToggle(title: "Detailed logging", detail: "Logs every window found, every move and every focus-follows-mouse change.",
                             isOn: $doc.config.debugLogging)
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Control Hyprthyst from a terminal, like hyprctl:")
                    Text("\(binaryPath) dispatch movefocus l\n\(binaryPath) dump\n\(binaryPath) reload")
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                    Text("dump writes the current layout state to the log. exec is only allowed from keyboard shortcuts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Command line")
            }
            Section("Backups") {
                LabeledContent {
                    Button("Back Up Now") {
                        if let url = doc.backUpShortcuts() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard shortcuts")
                        Text("Saves a dated copy next to the config file").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Reset") {
                LabeledContent("Keyboard shortcuts") {
                    Button("Restore Defaults…") {
                        if confirm("Restore the default keyboard shortcuts?", "Your own shortcuts will be replaced.") {
                            doc.restoreDefaultShortcuts()
                        }
                    }
                }
                LabeledContent("Everything") {
                    Button("Reset All Settings…") {
                        if confirm("Reset all settings to their defaults?", "Layouts, gaps, floating apps and shortcuts are all reset. Your main modifier is kept.") {
                            doc.resetEverything()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
