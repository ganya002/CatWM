import AppKit
import SwiftUI

// The five Settings panes. Each shows what most people need up front and keeps the rest in its own
// collapsed Advanced section; hidden settings keep working and the search still finds them.

// MARK: - General

struct GeneralPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        let s = ui.status
        VStack(alignment: .leading, spacing: 30) {
            StatusHero(ui: ui).setting("general.status", ui)

            OGroup("Startup") {
                OSwitchRow("Open at login", isOn: loginBinding)
                    .setting("general.login", ui)
                if s.loginNeedsApproval {
                    ORow("Waiting for approval", description: "Allow Ouch in Login Items", symbol: "exclamationmark.triangle.fill") {
                        OButton("Open Login Items", size: .sm) { LoginItem.openSettings() }
                    }
                }
                if !s.inputMonitoring && Hotkeys.shared.capsBound {
                    ORow("Instant Caps Lock shortcuts", description: "Needs Input Monitoring; otherwise Caps Lock waits for a hold") {
                        OButton("Allow…", size: .sm) { Permissions.requestInputMonitoring() }
                    }
                    .setting("general.inputMonitoring", ui)
                }
            }

            OGroup("Tiling") {
                OSwitchRow("Tile windows",
                           isOn: Binding(get: { ui.status.tilingEnabled }, set: { _ in
                               WindowManager.shared.toggleTiling()
                               ui.refreshStatus()
                           }))
                    .disabled(!s.running)
                    .setting("general.tiling", ui)
                ORow("Shortcut key", description: "The key you hold for most shortcuts") {
                    OMenuPicker(title: "Shortcut key", options: modifierOptions,
                                selection: Binding(get: { doc.modValue }, set: { doc.modValue = $0 }))
                }
                .setting("general.modifier", ui)
            }

            OGroup("Updates") {
                if updater.isConfigured {
                    OSwitchRow("Check for updates automatically",
                               isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.automaticallyChecks = $0 }))
                        .setting("general.autoCheck", ui)
                    if updater.automaticallyChecks {
                        OSwitchRow("Download updates automatically",
                                   isOn: Binding(get: { updater.automaticallyDownloads }, set: { updater.automaticallyDownloads = $0 }))
                            .setting("general.autoDownload", ui)
                            .transition(.opacity)
                    }
                    OSwitchRow("Include beta releases", description: "Get new versions early. They may have bugs.",
                               isOn: Binding(get: { updater.receivesBeta }, set: { updater.receivesBeta = $0 }))
                        .setting("general.beta", ui)
                    ORow("Check for updates", description: updater.lastChecked.map { "Last checked \($0.formatted(.relative(presentation: .named)))" }
                        ?? "Not checked yet") {
                        OButton("Check Now", icon: "arrow.down.circle", size: .sm) { updater.checkForUpdates() }
                    }
                    .setting("general.checkNow", ui)
                } else {
                    ORow("Updates aren't set up", description: "Release builds published with Amore update themselves")
                        .setting("general.checkNow", ui)
                }
            }
            .animation(Motion.easeOut, value: updater.automaticallyChecks)

            OGroup("Reset") {
                ORow("Reset all settings", description: "Layouts, gaps, floating apps and shortcuts. Your shortcut key stays.") {
                    OButton("Reset…", variant: .danger, size: .sm) {
                        if confirm("Reset all settings to their defaults?", "Resets layouts, gaps, floating apps and shortcuts. Your shortcut key is kept.") {
                            doc.resetEverything()
                        }
                    }
                }
                .setting("general.reset", ui)
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
}

/// Whether Ouch is working, straight on the pane: icon, a title, one line of detail, and the way to
/// fix it when it isn't. One layout for every state, so the icon stays put (and can bump) on a grant.
private struct StatusHero: View {
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let s = ui.status
        let live = s.trusted && s.keybindsActive && s.tilingEnabled
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                BadgedAppIcon(badge: !s.trusted ? "lock.circle.fill" : live ? "checkmark.circle.fill"
                                  : s.keybindsActive ? "pause.circle.fill" : "exclamationmark.circle.fill",
                              color: live ? Theme.success : Theme.warning, size: 52)
                    .squish(on: live, when: live)
                    .overlay(alignment: .topLeading) {
                        ImpactBurst(trigger: live, size: 22).offset(x: -12, y: -12).opacity(live ? 1 : 0)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(!s.trusted ? "Ouch needs Accessibility access" : !s.tilingEnabled ? "Tiling is paused"
                         : s.keybindsActive ? "Ouch is running" : "Keyboard shortcuts aren't active")
                        .font(Theme.body(22)).tracking(-0.2).oneLine()
                        .contentTransition(.opacity)
                    Text(s.trusted ? summary(s) : "macOS only lets apps move other apps' windows with this permission.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
                if s.trusted && !s.keybindsActive {
                    OButton("Retry", icon: "arrow.clockwise", size: .sm) { Hotkeys.shared.restart(); ui.refreshStatus() }
                }
            }
            if !s.trusted {
                VStack(alignment: .leading, spacing: 8) {
                    OStep(n: 1, text: "Click **Grant Access**. A guide appears next to System Settings.")
                    OStep(n: 2, text: "Turn on Ouch in the list.")
                    OStep(n: 3, text: "Still not working after a rebuild? Click **Reset Permission**, then turn it on again.")
                }
                HStack(spacing: 8) {
                    OButton("Grant Access", icon: "lock.open", variant: .primary) { Permissions.request() }
                    OButton("Reset Permission", variant: .ghost) { Permissions.reset() }
                    Spacer()
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Waiting…").font(Theme.body(12)).foregroundStyle(Theme.inkMuted)
                }
                .transition(.opacity)
            }
        }
        .animation(Motion.easeOut, value: s.trusted)
    }

    private func summary(_ s: WindowManager.Status) -> String {
        let w = "\(s.tiled) tiled window\(s.tiled == 1 ? "" : "s")"
        let f = s.floating > 0 ? " · \(s.floating) floating" : ""
        let d = " · \(s.screens.count) display\(s.screens.count == 1 ? "" : "s")"
        return w + f + d
    }
}

// MARK: - Layout

struct LayoutPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var drag = CycleDrag()

    private var allPadding: Binding<CGFloat> {
        Binding(get: { doc.config.paddingTop }, set: { v in
            doc.config.paddingTop = v; doc.config.paddingBottom = v; doc.config.paddingLeft = v; doc.config.paddingRight = v
        })
    }

    var body: some View {
        let c = doc.config
        let s = ui.status
        VStack(alignment: .leading, spacing: 30) {
            if s.trusted && !s.screens.isEmpty {
                OGroup("Displays") {
                    ForEach(s.screens, id: \.uuid) { screen in
                        HStack(spacing: 14) {
                            ScreenThumbnail(layout: screen.layout).frame(width: 56)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(screen.name).font(Theme.body(14)).oneLine()
                                Text(screen.workspace.isEmpty ? "Current layout" : "Workspace \(screen.workspace)")
                                    .font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                            }
                            Spacer(minLength: 8)
                            OMenuPicker(title: "Layout for \(screen.name)", options: Layout.allCases.map { ($0, $0.title) },
                                        selection: Binding(get: { screen.layout }, set: { l in
                                            WindowManager.shared.setLayout(l, screen: screen.uuid)
                                            ui.refreshStatus()
                                        }))
                        }
                        .frame(minHeight: 48).padding(.vertical, 8)
                    }
                }
                .setting("layout.displays", ui)
            }

            OGroup("Active layouts", footer: "Next Layout goes through these in order. Drag to change the order, or click one to remove it. Click a layout below to add it.") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: CycleChip.gap) {
                        ForEach(c.layouts, id: \.self) { l in
                            let i = c.layouts.firstIndex(of: l) ?? 0
                            CycleChip(index: i, layout: l, count: c.layouts.count, drag: drag, keys: moveKeys,
                                      move: { to in
                                          let to = min(max(to, 0), doc.config.layouts.count - 1)
                                          guard let from = doc.config.layouts.firstIndex(of: l), from != to else { return }
                                          withAnimation(Motion.snap(reduceMotion)) {
                                              doc.config.layouts.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                                          }
                                      },
                                      remove: {
                                          guard doc.config.layouts.count > 1 else { return }
                                          withAnimation(Motion.snap(reduceMotion)) { doc.config.layouts.removeAll { $0 == l } }
                                      })
                        }
                    }
                    .padding(.vertical, 10).padding(.horizontal, 8)
                    .coordinateSpace(name: CycleChip.space)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(Layout.allCases, id: \.self) { cell($0) }
                }
                .padding(.vertical, 10)
            }
            .setting("layout.cycle", ui)

            OGroup("Gaps") {
                GapsPreview(config: c, layout: c.layouts.first { ![.floating, .fullscreen].contains($0) } ?? .tall)
                    .frame(height: 170)
                    .padding(.vertical, 12)
                OSwitchRow("Gaps between windows", isOn: $doc.config.windowMargins).setting("layout.gaps", ui)
                ORow("Gap size") { points($doc.config.windowMarginSize, "Gap size") }
                    .disabled(!c.windowMargins)
                    .setting("layout.gapSize", ui)
                OSwitchRow("Smart gaps", description: "No gaps when a window is alone", isOn: $doc.config.smartWindowMargins)
                    .disabled(!c.windowMargins)
                    .setting("layout.smartGaps", ui)
                if ui.linkedPadding {
                    ORow("Screen padding", description: "Space between windows and the screen edges") { points(allPadding, "Screen padding") }
                        .setting("layout.padding", ui)
                } else {
                    ORow("Top padding") { points($doc.config.paddingTop, "Top padding") }.setting("layout.padding", ui)
                    ORow("Bottom padding") { points($doc.config.paddingBottom, "Bottom padding") }
                    ORow("Left padding") { points($doc.config.paddingLeft, "Left padding") }
                    ORow("Right padding") { points($doc.config.paddingRight, "Right padding") }
                }
                OSwitchRow("No padding on the built-in display", isOn: $doc.config.disablePaddingOnBuiltinDisplay)
                    .setting("layout.builtin", ui)
            }

            OGroup("Main pane") {
                ORow("Main pane resize step", description: "How much the split moves each time") {
                    OSlider(value: Binding(get: { Double(doc.config.windowResizeStep * 100) },
                                           set: { doc.config.windowResizeStep = CGFloat($0.rounded()) / 100 }),
                            range: 1...25, step: 1, ticks: [5], resetValue: 5, width: 160, label: "Main pane resize step",
                            format: { "\(Int($0))%" })
                }
                .setting("layout.resizeStep", ui)
            }

            OGroup("Feedback") {
                OSwitchRow("Show layout name on change", description: "A short card in the middle of the screen",
                           isOn: $doc.config.enablesLayoutHUD)
                    .setting("layout.hud", ui)
            }

            AdvancedSection(pane: .layout, ui: ui) {
                OGroup("Gaps and padding") {
                    OSwitchRow("Same padding on every side", isOn: Binding(get: { ui.linkedPadding }, set: { on in
                        withAnimation(Motion.easeOut) { ui.linkedPadding = on }
                        if on { allPadding.wrappedValue = c.paddingTop }
                    }))
                    .setting("layout.linked", ui)
                    OSwitchRow("Ignore menu bar when tiling", description: "Use this if you hide the menu bar", isOn: $doc.config.ignoreMenuBar)
                        .setting("layout.menuBar", ui)
                }
                OGroup("Feedback") {
                    OSwitchRow("Also when switching spaces", isOn: $doc.config.enablesLayoutHUDOnSpaceChange)
                        .disabled(!c.enablesLayoutHUD)
                        .setting("layout.hudSpaces", ui)
                }
            }
        }
    }

    /// The keys bound to focus left and right, so a focused layout moves with them as well as the arrows.
    private var moveKeys: (left: Set<String>, right: Set<String>) {
        var left = Set<String>(), right = Set<String>()
        for submap in doc.submaps {
            for a in doc.keyActions(in: submap) where a.row.dispatcher == "movefocus" && a.key.count == 1 {
                if a.arg == "l" { left.insert(a.key.lowercased()) } else if a.arg == "r" { right.insert(a.key.lowercased()) }
            }
        }
        return (left, right)
    }

    private func points(_ value: Binding<CGFloat>, _ label: String) -> some View {
        OSlider(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = CGFloat($0.rounded()) }),
                range: 0...60, step: 1, ticks: [10], resetValue: 10, width: 180, label: label, format: { "\(Int($0)) pt" })
    }

    private func cell(_ l: Layout) -> some View {
        let index = doc.config.layouts.firstIndex(of: l)
        let on = index != nil
        let locked = on && doc.config.layouts.count == 1
        return LayoutCell(layout: l, on: on) {
            withAnimation(Motion.snap(reduceMotion)) {
                if let index { if !locked { doc.config.layouts.remove(at: index) } } else { doc.config.layouts.append(l) }
            }
        }
    }
}

final class CycleDrag: ObservableObject {
    @Published var layout: Layout?
    @Published var x: CGFloat = 0
    var origin = 0
}

/// An active layout, numbered. Drag it to reorder, click it to remove it, or Tab to it and use the
/// arrow keys (or the keys you bound to focus left and right).
private struct CycleChip: View {
    static let width: CGFloat = 78
    static let gap: CGFloat = 12
    /// The row's own space: a chip's local space moves as it is reordered, which made the drag jitter.
    static let space = "cycleRow"
    let index: Int
    let layout: Layout
    let count: Int
    @ObservedObject var drag: CycleDrag
    let keys: (left: Set<String>, right: Set<String>)
    let move: (Int) -> Void
    let remove: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        let dragging = drag.layout == layout
        VStack(spacing: 6) {
            LayoutThumbnail(layout: layout, selected: true).frame(width: 72)
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)").font(Theme.body(11, .medium)).foregroundStyle(Theme.onAccent)
                        .contentTransition(.numericText())
                        .frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                        .offset(x: -6, y: -6)
                }
                .overlay(alignment: .topTrailing) {
                    if count > 1 {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(Theme.inkMuted))
                            .offset(x: 6, y: -6)
                            .opacity(hover.on && !dragging ? 1 : 0)
                            .scaleEffect(hover.on && !dragging ? 1 : 0.5)
                    }
                }
            Text(layout.shortTitle).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
                .frame(width: Self.width)
        }
        .frame(width: Self.width)
        .scaleEffect(dragging ? 1.06 : 1)
        .offset(x: dragging ? drag.x : 0)
        .zIndex(dragging ? 1 : 0)
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.fast), value: hover.on)
        .animation(.easeOut(duration: Theme.fast), value: dragging)
        .onTapGesture { remove() }
        .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .named(Self.space))
            .onChanged { v in
                if drag.layout != layout { drag.layout = layout; drag.origin = index }
                let target = min(max(drag.origin + Int((v.translation.width / (Self.width + Self.gap)).rounded()), 0), count - 1)
                drag.x = v.translation.width - CGFloat(target - drag.origin) * (Self.width + Self.gap)
                if target != index { move(target) }
            }
            .onEnded { _ in
                // Settle into the slot while it stops being lifted, instead of snapping.
                withAnimation(Motion.snap) { drag.x = 0; drag.layout = nil }
            })
        .focusable()
        .onKeyPress(phases: .down) { press in
            let c = press.characters.lowercased()
            if press.key == .leftArrow || keys.left.contains(c) { move(index - 1); return .handled }
            if press.key == .rightArrow || keys.right.contains(c) { move(index + 1); return .handled }
            if press.key == .delete || press.key == .deleteForward { remove(); return .handled }
            return .ignored
        }
        .accessibilityLabel("\(layout.title), \(index + 1) of \(count)")
        .accessibilityHint("Drag or use the arrow keys to move, click to remove")
    }
}

/// A display with its layout on it.
private struct ScreenThumbnail: View {
    let layout: Layout

    var body: some View {
        VStack(spacing: 2) {
            LayoutThumbnail(layout: layout, selected: true)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.borderControl, lineWidth: 1.5))
            Capsule().fill(Theme.borderControl).frame(width: 14, height: 2.5)
        }
    }
}

/// A layout in the grid; in the cycle it's lit and lands with a bump.
private struct LayoutCell: View {
    let layout: Layout
    let on: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            LayoutThumbnail(layout: layout, selected: on)
                .squish(on: on, when: on)
                .scaleEffect(hover.on ? 1.06 : 1)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(on ? Theme.accentSoft : hover.on ? Theme.wellHover : .clear))
                .overlay(alignment: .topLeading) {
                    ImpactBurst(trigger: on, size: 18).offset(x: -6, y: -6).opacity(on ? 1 : 0)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(Motion.spring, value: hover.on)
        .accessibilityLabel("\(layout.title), \(on ? "in the cycle" : "not in the cycle")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The main display, scaled down, with three windows placed exactly as the tiler would place them. They
/// spring to their new places as gaps and padding change.
struct GapsPreview: View {
    let config: Config
    let layout: Layout
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Desktop backdrop shared with the animation preview: a quiet wash of the palette.
    static let wallpaper = LinearGradient(colors: [Theme.accentSoft, Theme.tint], startPoint: .topLeading, endPoint: .bottomTrailing)

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
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Self.wallpaper)
                Rectangle().fill(Theme.ink.opacity(0.1)).frame(width: w, height: menuBar * scale)
                    .opacity(config.ignoreMenuBar ? 0 : 1)
                ForEach(Array(frames.enumerated()), id: \.offset) { i, f in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i == 0 ? Theme.accent : Theme.thumbMain)
                        .frame(width: max(f.width, 0), height: max(f.height, 0))
                        .position(x: f.midX, y: f.midY)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(width: g.size.width, height: g.size.height)
            // Dragging a slider retargets constantly, which a spring takes in stride.
            .animation(Motion.snap(reduceMotion), value: geometry)
        }
        .accessibilityHidden(true)
    }

    /// Everything from the settings that moves the windows.
    private var geometry: [CGFloat] {
        [config.paddingTop, config.paddingBottom, config.paddingLeft, config.paddingRight, config.windowMarginSize,
         config.windowMargins ? 1 : 0, config.ignoreMenuBar ? 1 : 0]
    }

    private func windows(in area: CGRect, scale: CGFloat) -> [CGRect] {
        let usable = CGRect(x: area.minX + config.paddingLeft * scale, y: area.minY + config.paddingTop * scale,
                            width: area.width - (config.paddingLeft + config.paddingRight) * scale,
                            height: area.height - (config.paddingTop + config.paddingBottom) * scale)
        let gap = (config.windowMargins ? config.windowMarginSize : 0) * scale
        guard usable.width > 4, usable.height > 4,
              let frames = layout.frames(count: 3, in: usable.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: 0.5, mainCount: 1)
        else { return [] }
        return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
    }
}

// MARK: - Windows

struct WindowsPane: View {
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
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Focus") {
                OSwitchRow("Focus follows mouse", description: "Hovering a window focuses it", isOn: $doc.config.focusFollowsMouse)
                    .setting("windows.ffm", ui)
                OSwitchRow("Mouse follows focus", description: "The pointer jumps to the window you focus", isOn: $doc.config.mouseFollowsFocus)
                    .setting("windows.mff", ui)
                OSwitchRow("Dim other windows", description: "Darkens everything but the focused window", isOn: $doc.config.dimOtherWindows)
                    .setting("windows.dimOthers", ui)
                ORow("Dim strength", description: "How dark the other windows get") {
                    OSlider(value: Binding(get: { Double(doc.config.dimStrength * 100) },
                                           set: { doc.config.dimStrength = CGFloat($0.rounded()) / 100 }),
                            range: 0...100, step: 1, ticks: [30], resetValue: 30, width: 160, label: "Dim strength",
                            format: { "\(Int($0))%" })
                }
                .disabled(!doc.config.dimOtherWindows)
                .setting("windows.dimStrength", ui)
                OSwitchRow("Blur other windows", description: "Softens everything but the focused window", isOn: $doc.config.blurOtherWindows)
                    .setting("windows.blurOthers", ui)
                ORow("Blur radius", description: "How soft the other windows look") {
                    OSlider(value: Binding(get: { Double(doc.config.blurRadius) },
                                           set: { doc.config.blurRadius = CGFloat($0.rounded()) }),
                            range: 2...60, step: 1, ticks: [20], resetValue: 20, width: 160, label: "Blur radius",
                            format: { "\(Int($0)) pt" })
                }
                .disabled(!doc.config.blurOtherWindows)
                .setting("windows.blurRadius", ui)
            }

            OGroup("Mouse") {
                OSwitchRow("Drag to swap", description: "Drop a window on another to trade places", isOn: $doc.config.mouseSwapsWindows)
                    .setting("windows.dragSwap", ui)
                OSwitchRow("Drag window edges to resize the main pane",
                           description: "Resize a tiled window with the mouse, and the main pane follows", isOn: $doc.config.mouseResizesWindows)
                    .setting("windows.resizeMain", ui)
            }

            OGroup("Floating") {
                ORow("Apps in the list", description: doc.config.floatingIsBlacklist ? "Float; everything else tiles" : "Are the only ones that tile") {
                    OSegmented(title: "Apps in the list", options: [(true, "Float"), (false, "Tile")],
                               selection: $doc.config.floatingIsBlacklist)
                }
                .setting("windows.floatingMode", ui)
                if doc.config.floating.isEmpty {
                    ORow("No apps yet", description: "Add one that's running, or by bundle ID under Advanced") { addMenu }
                } else {
                    ForEach(doc.config.floating, id: \.self) { id in
                        HStack(spacing: 12) {
                            appIcon(id)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(appName(id) ?? id).font(Theme.body(14)).oneLine()
                                if appName(id) != nil { Text(id).font(Theme.mono(11, .regular)).foregroundStyle(Theme.inkMuted).oneLine(.middle) }
                            }
                            Spacer(minLength: 0)
                            RemoveButton(help: "Remove \(appName(id) ?? id)") {
                                withAnimation(Motion.easeOut) { doc.config.floating.removeAll { $0 == id } }
                            }
                        }
                        .frame(minHeight: 48).padding(.vertical, 6)
                    }
                    HStack { Spacer(); addMenu }.padding(.vertical, 10)
                }
            }

            OGroup("Workspaces") {
                OSwitchRow("Use Ouch workspaces", description: "Instant, per-display workspaces instead of macOS Spaces",
                           isOn: $doc.config.virtualWorkspaces)
                    .setting("windows.workspaces", ui)
                ORow("Sort windows by", description: "How the Sort Windows panel groups them when it opens") {
                    OMenuPicker(title: "Sort windows by", options: SortStrategy.allCases.map { ($0, $0.title) },
                                selection: $doc.config.sortStrategy)
                }
                .disabled(!doc.config.virtualWorkspaces)
                .setting("windows.sortStrategy", ui)
                OSwitchRow("Suggest sorting a crowded workspace", description: "A tip under the menu bar icon, at most once a day",
                           isOn: Binding(get: { doc.config.sortNudge > 0 }, set: { doc.config.sortNudge = $0 ? 5 : 0 }))
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting("windows.sortNudge", ui)
                ORow("Crowded from", description: "Windows on one workspace") {
                    OSlider(value: Binding(get: { Double(doc.config.sortNudge) },
                                           set: { doc.config.sortNudge = Int($0.rounded()) }),
                            range: Double(min(3, doc.config.sortNudge))...Double(max(20, doc.config.sortNudge)), step: 1, ticks: [5], resetValue: 5, width: 160, label: "Crowded from",
                            format: { "\(Int($0)) windows" })
                }
                .disabled(!doc.config.virtualWorkspaces || doc.config.sortNudge == 0)
                .setting("windows.sortCrowded", ui)
            }

            AdvancedSection(pane: .windows, ui: ui) {
                OGroup("Windows") {
                    OSwitchRow("New windows become main", isOn: $doc.config.newWindowsToMain).setting("windows.newMain", ui)
                    OSwitchRow("Float small windows", description: "Dialogs and panels stay put", isOn: $doc.config.floatSmallWindows)
                        .setting("windows.floatSmall", ui)
                    ORow("Add app by bundle ID", description: "Wildcards like com.adobe.* work too") {
                        OTextField(placeholder: "com.example.app", text: $ui.newID, mono: true, onSubmit: add).frame(width: 190)
                        OButton("Add", size: .sm, action: add)
                            .disabled(ui.newID.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .setting("windows.bundleID", ui)
                }
                OGroup("Workspaces") {
                    OSwitchRow("Stay on this workspace when closing a window", isOn: $doc.config.stayOnWorkspaceAfterClose)
                        .disabled(!doc.config.virtualWorkspaces)
                        .setting("windows.stay", ui)
                    ORow("Home Desktop", description: WindowManager.shared.homeSpaceSummary.isEmpty ? "The Desktop you're on when Ouch starts"
                        : "Workspaces live on \(WindowManager.shared.homeSpaceSummary)") {
                        OButton("Use This Desktop", size: .sm) { WindowManager.shared.makeCurrentSpaceHome() }
                    }
                    .disabled(!doc.config.virtualWorkspaces)
                    .setting("windows.home", ui)
                }
            }
        }
    }

    private var addMenu: some View {
        let doc = doc, apps = runningApps
        return OMenuButton(style: OButtonStyle(variant: .secondary, size: .sm), items: {
            apps.map { app in
                MenuItem(id: app.id, label: app.name, image: app.icon.map(resized), enabled: !doc.config.floating.contains(app.id), action: {
                    if !doc.config.floating.contains(app.id) { withAnimation(Motion.easeOut) { doc.config.floating.append(app.id) } }
                })
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11.5, weight: .medium))
                Text("Add Running App")
            }
        }
        .fixedSize()
    }

    private func add() {
        let id = ui.newID.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !doc.config.floating.contains(id) else { return }
        withAnimation(Motion.easeOut) { doc.config.floating.append(id) }
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
        } else {
            RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                .frame(width: 26, height: 26).padding(1)
        }
    }
}

// MARK: - Motion

struct MotionPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    /// The preview's two windows: a random pair, one light and one dark so they never blend.
    static let previewApps = [DemoApp.all.filter(\.dark).randomElement()!, DemoApp.all.filter { !$0.dark }.randomElement()!].shuffled()

    struct Preset {
        let name: String
        var animate = true
        var curve: AnimationCurve = .easeOut
        var duration = 0.2
        var bounce = 0.5
    }

    static let presets: [Preset] = [
        Preset(name: "None", animate: false),
        Preset(name: "Snappy", duration: 0.12),
        Preset(name: "Smooth", duration: 0.2),
        Preset(name: "Relaxed", curve: .easeInOut, duration: 0.35),
        Preset(name: "Springy", curve: .spring, duration: 0.5, bounce: 0.55),
        Preset(name: "Wobbly", curve: .spring, duration: 0.8, bounce: 0.85),
        Preset(name: "Bouncy", curve: .bounce, duration: 0.6, bounce: 0.5),
        Preset(name: "Playful", curve: .overshoot, duration: 0.35, bounce: 0.6),
    ]

    private func matches(_ p: Preset, _ c: Config) -> Bool {
        guard p.animate else { return !c.animate }
        return c.animate && c.animationCurve == p.curve && abs(c.animationDuration - p.duration) < 0.005
            && (!p.curve.usesBounce || abs(c.animationBounce - p.bounce) < 0.005)
    }

    var body: some View {
        let c = doc.config
        VStack(alignment: .leading, spacing: 30) {
            OGroup("Style") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Self.presets, id: \.name) { p in
                        PresetTile(preset: p, selected: matches(p, c)) {
                            doc.config.animate = p.animate
                            if p.animate {
                                doc.config.animationCurve = p.curve
                                doc.config.animationDuration = p.duration
                                if p.curve.usesBounce { doc.config.animationBounce = p.bounce }
                            }
                            play() // feel it right away
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .setting("motion.style", ui)

            OGroup("Preview") {
                preview
                    .frame(height: 150)
                    .padding(.vertical, 10)
                ORow("Play it again", description: "Plays with exactly the curve windows use") {
                    OButton("Play", icon: "play.fill", size: .sm, action: play)
                }
            }
            .setting("motion.preview", ui)

            OGroup("Feel") {
                OSwitchRow("Animate windows", description: "Windows glide to their new place", isOn: $doc.config.animate)
                    .setting("motion.animate", ui)
                OBarSlider(value: Binding(get: { c.animationDuration }, set: { doc.config.animationDuration = ($0 * 100).rounded() / 100 }),
                           range: 0.05...1, step: 0.01, label: "Duration", symbol: "timer",
                           format: { "\(Int(($0 * 1000).rounded())) ms" }, onCommit: play)
                    .padding(.vertical, 12)
                    .disabled(!c.animate)
                    .setting("motion.duration", ui)
            }

            AdvancedSection(pane: .motion, ui: ui) {
                OGroup("Curve") {
                    ORow("Curve", description: "How windows speed up and settle") {
                        OMenuPicker(title: "Curve",
                                    options: AnimationCurve.named.map { ($0.name, $0.title) } + [("bezier", AnimationCurve.bezier(0, 0, 0, 0).title)],
                                    selection: Binding(get: { c.animationCurve.isBezier ? "bezier" : c.animationCurve.name }, set: { name in
                                        if name == "bezier" {
                                            if !c.animationCurve.isBezier { doc.config.animationCurve = .bezier(0.34, 1.56, 0.64, 1) }
                                        } else if let curve = AnimationCurve(name) {
                                            doc.config.animationCurve = curve
                                        }
                                        play()
                                    }))
                    }
                    .disabled(!c.animate)
                    .setting("motion.curve", ui)
                    if case let .bezier(x1, y1, x2, y2) = c.animationCurve {
                        ORow("Control points", description: "x1, y1, x2, y2 as in CSS; y past 1 overshoots") {
                            OTextField(placeholder: "0.34, 1.56, 0.64, 1", text: $ui.bezierText, mono: true, onSubmit: play)
                                .frame(width: 170)
                                .onAppear { ui.bezierText = Self.points(x1, y1, x2, y2) }
                                .onChange(of: c.animationCurve) { _, new in
                                    if case let .bezier(a, b, c, d) = new, AnimationCurve(ui.bezierText) != new { ui.bezierText = Self.points(a, b, c, d) }
                                }
                                .onChange(of: ui.bezierText) { _, text in
                                    if let curve = AnimationCurve(text), curve.isBezier { doc.config.animationCurve = curve }
                                }
                        }
                        .disabled(!c.animate)
                        .setting("motion.bezier", ui)
                    }
                    OBarSlider(value: Binding(get: { c.animationBounce }, set: { doc.config.animationBounce = ($0 * 100).rounded() / 100 }),
                               range: 0...1, step: 0.01, label: "Bounciness", symbol: "sparkles",
                               format: { "\(Int(($0 * 100).rounded()))%" }, onCommit: play)
                        .padding(.vertical, 12)
                        .disabled(!c.animate || !c.animationCurve.usesBounce)
                        .tooltip("How far springs swing, balls bounce and overshoot goes")
                        .setting("motion.bounce", ui)
                }
                OGroup("Panels and window mode") {
                    ORow("Panel animation", description: "How Sort Windows and keyboard help come and go") {
                        HStack(spacing: 8) {
                            OMenuPicker(title: "Panel animation", options: PanelMotion.allCases.map { ($0.rawValue, $0.title) },
                                        selection: Binding(get: { c.panelAnimation.rawValue }, set: { raw in
                                            guard let m = PanelMotion(rawValue: raw) else { return }
                                            doc.config.panelAnimation = m
                                            PanelMotionDemo.play([m], keyboardOnly: true)
                                        }))
                            OButton("Play", icon: "play.fill", size: .sm) { PanelMotionDemo.play([c.panelAnimation], keyboardOnly: true) }
                        }
                    }
                    .setting("motion.panels", ui)
                    ORow("Window mode effect", description: "Shown at the screen edges while window mode is on") {
                        HStack(spacing: 8) {
                            OMenuPicker(title: "Window mode effect", options: ModeFX.Style.allCases.map { ($0.rawValue, $0.title) },
                                        selection: Binding(get: { c.modeEffect.rawValue }, set: { raw in
                                            guard let s = ModeFX.Style(rawValue: raw) else { return }
                                            doc.config.modeEffect = s
                                            ModeFX.shared.command([s.rawValue])
                                        }))
                            OButton("Play", icon: "play.fill", size: .sm) { ModeFX.shared.command([c.modeEffect.rawValue]) }
                                .disabled(c.modeEffect == .none)
                        }
                    }
                    .setting("motion.modeEffect", ui)
                }
            }
        }
    }

    private var preview: some View {
        let c = doc.config
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, flipped = ui.previewFlipped
            let seam = flipped ? w * 0.65 - 2 : w * 0.6 - 2
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GapsPreview.wallpaper)
                DemoWindow(app: Self.previewApps[0], main: true, corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.35 : w * 0.6) - 12), height: h - 16)
                    .offset(x: flipped ? w * 0.65 + 4 : 8, y: 8)
                DemoWindow(app: Self.previewApps[1], corner: 5)
                    .frame(width: max(1, (flipped ? w * 0.65 : w * 0.4) - 12), height: h - 16)
                    .offset(x: flipped ? 8 : w * 0.6 + 4, y: 8)
                // The windows meet at the seam when they land.
                ImpactBurst(trigger: flipped, angle: -90, size: 26,
                            delay: c.animate ? c.animationDuration * c.animationCurve.arrival(bounce: c.animationBounce) : 0)
                    .offset(x: seam - 13, y: -4)
                    .animation(nil, value: flipped)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture(perform: play)
        }
        .accessibilityHidden(true)
    }

    private static func points(_ v: Double...) -> String { v.map { String(format: "%g", $0) }.joined(separator: ", ") }

    private func play() {
        let c = doc.config
        // Exactly the curve the real animator uses.
        withAnimation(c.animate ? Animation(CurveAnimation(curve: c.animationCurve, bounce: c.animationBounce, duration: c.animationDuration)) : nil) {
            ui.previewFlipped.toggle()
        }
    }
}

/// SwiftUI animation that follows an `AnimationCurve`, so the preview moves like real windows do.
struct CurveAnimation: CustomAnimation {
    let curve: AnimationCurve
    let bounce: Double
    let duration: Double

    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard time < duration else { return nil }
        return value.scaled(by: curve.progress(time / duration, bounce: bounce))
    }
}

/// Plot of a curve's progress over time: a soft gradient under a rounded line, ending in a dot.
private struct CurveGraph: View {
    let curve: AnimationCurve
    let bounce: Double
    var instant = false
    var lineWidth: CGFloat = 2
    var color: Color = Theme.accent

    var body: some View {
        Canvas { ctx, size in
            // Leave headroom above and below for overshoot and anticipation, and room for the end dot.
            let inset: CGFloat = 4
            let w = size.width - inset * 2, h = size.height - inset * 2
            let samples = (0...120).map { Double($0) / 120 }
            let values = samples.map { instant ? ($0 > 0 ? 1 : 0) : curve.progress($0, bounce: bounce) }
            let lo = min(0, values.min() ?? 0), hi = max(1, values.max() ?? 1)
            func y(_ v: Double) -> CGFloat { inset + h - CGFloat((v - lo) / (hi - lo)) * h }
            let points = zip(samples, values).map { CGPoint(x: inset + CGFloat($0) * w, y: y($1)) }
            var line = Path()
            for (i, p) in points.enumerated() { if i == 0 { line.move(to: p) } else { line.addLine(to: p) } }
            var area = line
            area.addLine(to: CGPoint(x: inset + w, y: y(0)))
            area.addLine(to: CGPoint(x: inset, y: y(0)))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                 startPoint: CGPoint(x: 0, y: inset), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            if let end = points.last {
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
    }
}

/// A preset as a tile with its curve: outlined in `accent` when it's the current style.
private struct PresetTile: View {
    let preset: MotionPane.Preset
    let selected: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                CurveGraph(curve: preset.animate ? preset.curve : .linear, bounce: preset.bounce, instant: !preset.animate,
                           lineWidth: 2, color: Theme.accent)
                    .frame(height: 34)
                    .padding(.horizontal, 8)
                Text(preset.name).font(Theme.body(12.5, selected ? .medium : .regular)).oneLine()
                    .foregroundStyle(selected ? Theme.accentInk : Theme.ink)
            }
            .padding(.vertical, 12).padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(selected ? Theme.accentSoft : hover.on ? Theme.wellHover : Theme.well))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 1.5).opacity(selected ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        }
        .buttonStyle(PressScale())
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.medium), value: selected)
        .accessibilityLabel(preset.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Shortcuts

/// The action catalog as menu items: a submenu per category, numbered families folded into their own submenu.
enum ActionMenuItems {
    static func items(current: Action? = nil, pick: @escaping (Action) -> Void) -> [MenuItem] {
        func row(_ a: Action, _ title: String) -> MenuItem {
            MenuItem(id: "a.\(a.id)", kind: current == nil ? .action : .radio, label: title, checked: a.id == current?.id,
                     action: { pick(a) })
        }
        func sub(_ id: String, _ label: String, symbol: String?, _ children: [MenuItem]) -> MenuItem {
            MenuItem(id: id, kind: .sub, label: label, symbol: symbol, width: MenuItem.fitWidth(children), children: children)
        }
        return Actions.byCategory.map { cat, actions in
            sub("c.\(cat.rawValue)", cat.rawValue, symbol: cat.symbol, Actions.menuEntries(actions).map { entry in
                switch entry {
                case .action(let a): row(a, a.title)
                case .group(let name, let list): sub("g.\(name)", name, symbol: nil, list.map { row($0, $0.short ?? $0.title) })
                }
            })
        }
    }
}

struct ShortcutsPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    private var keyboardFinishOptions: [(value: String, label: String)] {
        var options = [
            (value: "auto", label: "Auto (this Mac)"),
            (value: "macbook-pro", label: "MacBook Pro (family)"),
            (value: "macbook-air", label: "MacBook Air (family)"),
            (value: "macbook-neo", label: "MacBook Neo (family)"),
            (value: "magic-keyboard", label: "Magic Keyboard (family)"),
        ] + MacKeyboard.Finish.all.map { (value: $0.slug, label: $0.name) }
        if !options.contains(where: { $0.value == doc.config.keyboardFinish }) {
            options.append((value: doc.config.keyboardFinish, label: doc.config.keyboardFinish))
        }
        return options
    }

    /// How to open keyboard help, from the shortcut that enters window mode right now.
    private var keyboardHelpHint: String {
        let enter = doc.binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && $0.args.lowercased() != "reset" }
        guard let enter, let flags = ConfigDocument.flags(doc.resolvedMods(enter.mods)) else { return "Press \(doc.config.keyboardHelpKey) in window mode" }
        let hold = ConfigDocument.modifierCaps(flags.subtracting(.shift)).joined()
        return hold.isEmpty ? "Press \(doc.config.keyboardHelpKey) in window mode" : "Hold \(hold) after \(doc.prettyShortcut(enter).joined()), or press \(doc.config.keyboardHelpKey) in window mode"
    }

    private func category(_ r: BindRow) -> ActionCategory {
        Actions.match(r)?.category ?? Actions.rangeSummary(r)?.category ?? .custom
    }

    private func matches(_ r: BindRow) -> Bool {
        guard r.submap == ui.bindMode else { return false }
        guard !ui.shortcutFilter.isEmpty else { return true }
        let q = ui.shortcutFilter.lowercased()
        return [doc.title(r), r.dispatcher, r.args, r.key, doc.prettyShortcut(r).joined()].contains { $0.lowercased().contains(q) }
    }

    var body: some View {
        let sections = ActionCategory.allCases.map { cat in (cat, doc.binds.filter { category($0) == cat && matches($0) }) }
            .filter { !$0.1.isEmpty }
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                if doc.submaps.count > 1 {
                    OSegmented(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                               selection: $ui.bindMode)
                        .tooltip("Global shortcuts work everywhere. Mode shortcuts only work in the mode, so single keys are fine.")
                }
                OTextField(placeholder: "Filter shortcuts", text: $ui.shortcutFilter).frame(maxWidth: 200)
                Spacer(minLength: 0)
                addMenu
                OIconButton(symbol: "keyboard", label: "Shortcut map", variant: .secondary) {
                    withAnimation(Motion.snap) { ui.showMap = true }
                }
                .setting("shortcuts.map", ui)
            }
            .setting("shortcuts.list", ui)

            OGroup("Keyboard") {
                OSwitchRow("Show keyboard help",
                           description: keyboardHelpHint,
                           isOn: $doc.config.keyboardHelp)
                    .setting("shortcuts.keyboardHelp", ui)
                ORow("Keyboard finish", description: "Used by keyboard help and Shortcut Map") {
                    OMenuPicker(title: "Keyboard finish", options: keyboardFinishOptions, selection: $doc.config.keyboardFinish)
                }
                .setting("shortcuts.keyboardFinish", ui)
            }

            ForEach(sections, id: \.0) { cat, rows in
                OGroup(cat.rawValue) {
                    ForEach(rows) { row in
                        BindRowView(doc: doc, ui: ui, rowID: row.id).setting("bind.\(row.id)", ui)
                    }
                }
            }
            if sections.isEmpty {
                Text(ui.shortcutFilter.isEmpty ? "No shortcuts yet" : "No shortcuts match “\(ui.shortcutFilter)”")
                    .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .onDisappear { ui.recording = nil }
    }

    private var addMenu: some View {
        OMenuButton(style: OButtonStyle(variant: .primary), items: {
            let ranges: [MenuItem] = [
                MenuItem(id: "r.ws", label: "Go to Workspaces 1–10 with 1…0", action: { add("workspace", "1..10", key: "1..0") }),
                MenuItem(id: "r.mv", label: "Move Window to Workspaces 1–10 with 1…0", action: { add("movetoworkspace", "1..10", key: "1..0") }),
                .sep("r.s1"),
                MenuItem(id: "r.fh", label: "Focus with H J K L", action: { add("movefocus", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.fa", label: "Focus with Arrow Keys", action: { add("movefocus", "l|d|u|r", key: "left|down|up|right") }),
                MenuItem(id: "r.mh", label: "Move Window with H J K L", action: { add("movewindow", "l|d|u|r", key: "h|j|k|l") }),
                MenuItem(id: "r.ma", label: "Move Window with Arrow Keys", action: { add("movewindow", "l|d|u|r", key: "left|down|up|right") }),
                .sep("r.s2"),
                MenuItem(id: "r.custom", label: "Custom Range…", action: { add("workspace", "1..5", key: "1..5", expand: true) }),
            ]
            return ActionMenuItems.items { a in add(a.dispatcher, a.args) } + [
                MenuItem(id: "ranges", kind: .sub, label: "Ranges", symbol: "ellipsis.rectangle", width: MenuItem.fitWidth(ranges), children: ranges),
                .sep("s"),
                // Matches no preset, so the raw editor shows.
                MenuItem(id: "custom", label: "Custom Dispatcher…", symbol: "terminal", action: { add("layoutmsg", "") }),
            ]
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                Text("Add Shortcut")
            }
        }
        .fixedSize()
    }

    private func add(_ dispatcher: String, _ args: String, key: String = "", expand: Bool = false) {
        let row = BindRow(mods: ui.bindMode.isEmpty ? doc.modVarName : "", key: key, dispatcher: dispatcher, args: args,
                          submap: ui.bindMode)
        doc.binds.append(row)
        if expand { ui.expanded.insert(row.id) }
        ui.shortcutFilter = ""
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
            let summary = isRange ? Actions.rangeSummary(row) : nil
            // Range rows read like any other row; their keys and values open on demand (or when they're broken).
            let editorOpen = isRange && (ui.expanded.contains(rowID) || summary == nil || issue?.severity == .error)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Recorder(doc: doc, ui: ui, row: row)
                    if isRange {
                        Text(summary?.title ?? "Custom range").font(Theme.body(14)).oneLine(.middle)
                            .foregroundStyle(summary == nil ? Theme.inkMuted : Theme.ink)
                        Spacer(minLength: 0)
                    } else {
                        actionMenu(i, action)
                        if row.dispatcher == "exec" {
                            OTextField(placeholder: "open -na Terminal", text: $doc.binds[i].args, mono: true)
                        } else if action == nil {
                            OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                            OTextField(placeholder: "arguments", text: $doc.binds[i].args, mono: true)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    if let issue {
                        Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                            .tooltip(issue.message)
                            .accessibilityLabel(issue.message)
                    }
                    if isRange { editToggle(open: editorOpen, locked: summary == nil || issue?.severity == .error) }
                    RemoveButton(help: "Delete shortcut") {
                        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == rowID } }
                        ui.expanded.remove(rowID)
                    }
                }
                if editorOpen {
                    rangeEditor(i, row, valid: issue?.severity != .error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let issue, issue.severity == .error {
                    Text(issue.message).font(Theme.body(12)).foregroundStyle(Theme.danger).oneLine()
                        .padding(.leading, Recorder.width + 12)
                }
            }
            .frame(minHeight: 48)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.reveal == rowID ? 1 : 0)
            }
        }
    }

    /// Dispatcher, keys and values of a range row, with what each key ends up doing.
    private func rangeEditor(_ i: Int, _ row: BindRow, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                OTextField(placeholder: "1..0", text: $doc.binds[i].key, mono: true).frame(minWidth: 90, maxWidth: 150)
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                OTextField(placeholder: "1..10", text: $doc.binds[i].args, mono: true).frame(minWidth: 90, maxWidth: 150)
                Spacer(minLength: 0)
            }
            if valid {
                Text(rangePreview(row)).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.leading, Recorder.width + 12)
    }

    private func editToggle(open: Bool, locked: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                if ui.expanded.contains(rowID) { ui.expanded.remove(rowID) } else { ui.expanded.insert(rowID) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(open ? Theme.accentInk : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(open ? Theme.accentSoft : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .tooltip(open ? "Hide keys and values" : "Edit keys and values")
        .accessibilityLabel(open ? "Hide keys and values" : "Edit keys and values")
    }

    /// "H → Focus Left · J → Focus Down · …", or the raw values when they aren't catalog actions.
    private func rangePreview(_ row: BindRow) -> String {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return "" }
        let mods = ConfigDocument.flags(doc.resolvedMods(row.mods)).map { ConfigDocument.modifierCaps($0).joined() } ?? ""
        func one(_ p: (key: String, arg: String)) -> String {
            let target = Actions.match(BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: p.arg))?.title
                ?? (p.arg.isEmpty ? row.dispatcher : p.arg)
            return "\(mods)\(ConfigDocument.capLabel(p.key)) → \(target)"
        }
        let shown = pairs.count > 5 ? pairs.prefix(3).map(one) + ["…", one(pairs.last!)] : pairs.map(one)
        return shown.joined(separator: "  ·  ")
    }

    private func actionMenu(_ i: Int, _ action: Action?) -> some View {
        let doc = doc
        return OMenuButton(items: {
            ActionMenuItems.items(current: action) { a in
                guard doc.binds.indices.contains(i) else { return }
                doc.binds[i].dispatcher = a.dispatcher
                if a.dispatcher != "exec" || doc.binds[i].args.isEmpty || action?.dispatcher != "exec" {
                    doc.binds[i].args = a.args
                }
            }
        }) {
            HStack(spacing: 5) {
                Text(action?.title ?? "Custom").font(Theme.body(14)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
        }
        .fixedSize()
    }
}

/// Click to record a shortcut: keycaps on a sunken well, an `accent` outline while listening.
private struct Recorder: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let row: BindRow
    static let width: CGFloat = 150

    var body: some View {
        let recording = ui.recording == row.id
        Button {
            ui.recording = recording ? nil : row.id
        } label: {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle").font(.system(size: 11, weight: .semibold))
                        Text(BindRange.isRange(row.key) ? "Press modifiers…" : "Press keys…")
                    }
                    .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.accentInk).oneLine()
                } else if row.key.isEmpty {
                    Text("Click to record").font(Theme.body(12.5)).foregroundStyle(Theme.inkFaint).oneLine()
                } else {
                    // Freshly recorded keys drop in with a little bump.
                    Kbd(keys: doc.prettyShortcut(row)).squish(on: row.mods + row.key, anchor: .center)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.width, height: 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(recording ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(recording ? Theme.accent : Theme.hairline,
                              style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(recording ? (row.submap.isEmpty || BindRange.isRange(row.key) ? "Esc cancels" : "Click to cancel")
              : "Click to record a new shortcut")
        .accessibilityLabel(recording ? "Recording shortcut" : "Shortcut \(doc.prettyShortcut(row).joined()). Click to record")
    }
}
