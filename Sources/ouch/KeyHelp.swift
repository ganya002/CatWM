import AppKit
import SwiftUI

/// On-screen keyboard help: the whole keyboard with every action written on its key, shown only on
/// request. In a mode it appears when you keep holding the chord's modifier (⌘ for ⌘⇪) for half a
/// second after entering, and goes when you let go; `?` in the mode toggles it; the menu bar's
/// Keyboard Help shows it until the next click or key. A click-through, non-activating panel centred
/// on the screen with the focused window. `keyboard-help = false` in the config turns it off.
final class KeyHelp {
    static let shared = KeyHelp()

    private let model = KeyHelpModel()
    private var panel: NSPanel?
    private var host: NSHostingView<KeyHelpView>?
    private var holdWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?
    private var dismissMonitor: Any?
    /// The modifiers that entered the current mode (⌘ for ⌘⇪); holding them on keeps the help up.
    private var chordMods: NSEvent.ModifierFlags = []
    private static let margin: CGFloat = 40
    private static let holdDelay = 0.5

    private var enabled: Bool { WindowManager.shared.config.keyboardHelp }
    var isVisible: Bool { model.shown }

    /// Hooks into the key tap. Called once when the window manager starts.
    func install() {
        Hotkeys.shared.onFlagsChanged = { [weak self] f in self?.flagsChanged(Self.mods(f)) }
        Hotkeys.shared.onFire = { [weak self] b in self?.fired(b) }
        Hotkeys.shared.onHelpKey = { [weak self] in self?.toggle() }
    }

    // MARK: Triggers

    /// A mode began or ended. Entering with a modifier still down arms the hold timer.
    func modeChanged(_ name: String) {
        holdWork?.cancel()
        guard !name.isEmpty else {
            if model.shown && model.reason != .menu { hide() }
            return
        }
        if model.shown {
            // Shown from the menu, then the mode came on: follow it, and stay until `?` or the mode ends.
            show(mode: name, reason: .toggle)
            return
        }
        guard enabled else { return }
        chordMods = Self.mods(CGEventSource.flagsState(.combinedSessionState)).subtracting(.shift)
        guard !chordMods.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, Hotkeys.shared.submap == name,
                  Self.mods(CGEventSource.flagsState(.combinedSessionState)).isSuperset(of: chordMods) else { return }
            show(mode: name, reason: .hold)
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
    }

    /// `?` in a mode.
    func toggle() {
        let mode = Hotkeys.shared.submap
        if model.shown { hide(); return }
        guard enabled, !mode.isEmpty else { return }
        holdWork?.cancel()
        show(mode: mode, reason: .toggle)
    }

    /// The menu bar's Keyboard Help: the current mode's keys (global ones outside a mode).
    func showFromMenu() {
        holdWork?.cancel()
        let mode = Hotkeys.shared.submap
        show(mode: mode, reason: mode.isEmpty ? .menu : .toggle)
    }

    private func flagsChanged(_ f: NSEvent.ModifierFlags) {
        if holdWork != nil, !f.isSuperset(of: chordMods) { holdWork?.cancel(); holdWork = nil }
        guard model.shown else { return }
        if model.reason == .hold, !f.isSuperset(of: chordMods) { hide(); return }
        if model.held != f { model.held = f }
    }

    private func fired(_ b: KeyBinding) {
        guard model.shown, b.submap == model.mode, b.keyCode < 0x1000 else { return }
        model.flashes[b.keyCode, default: 0] += 1
    }

    // MARK: Panel

    private func show(mode: String, reason: KeyHelpModel.Reason) {
        orderOutWork?.cancel()
        let screen = WindowManager.shared.focusedScreen
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let wasShown = model.shown
        model.load(mode: mode, binds: WindowManager.shared.config.bindings, chord: chordMods, reason: reason,
                   room: screen.visibleFrame.width - Self.margin * 2 - 48)
        model.held = Self.mods(CGEventSource.flagsState(.combinedSessionState))

        let p = panel ?? makePanel()
        panel = p
        let host = host ?? NSHostingView(rootView: KeyHelpView(model: model, margin: Self.margin))
        if self.host == nil { self.host = host; p.contentView = host }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let area = screen.visibleFrame
        p.setFrame(CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
                   display: true)
        p.orderFrontRegardless()
        // A turn later, so the view sees `shown` change and fades and scales in.
        if !wasShown { DispatchQueue.main.async { [weak self] in self?.model.shown = true } }

        setDismissMonitor(reason == .menu)
    }

    func hide() {
        holdWork?.cancel()
        setDismissMonitor(false)
        guard model.shown else { return }
        model.shown = false
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.medium + 0.05, execute: work)
    }

    /// Shown from the menu, the help stays until the next click or key press anywhere.
    private func setDismissMonitor(_ on: Bool) {
        if let m = dismissMonitor { NSEvent.removeMonitor(m); dismissMonitor = nil }
        guard on else { return }
        // After the click that picked the menu item has finished.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, model.shown, model.reason == .menu, dismissMonitor == nil else { return }
            dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] _ in
                self?.hide()
            }
        }
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // drawn by SwiftUI, so it follows the scale
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        return p
    }

    static func mods(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(f.rawValue)).intersection([.command, .option, .control, .shift])
    }
}

// MARK: - Model

final class KeyHelpModel: ObservableObject {
    enum Reason { case hold, toggle, menu }

    @Published var shown = false
    @Published var mode = ""
    @Published var reason: Reason = .hold
    /// Modifiers held right now; ⇧ picks the layer and held keys get a ring.
    @Published var held: NSEvent.ModifierFlags = []
    /// Presses per key while the help is up, so each one flashes. Only ever counts up: going back to
    /// zero would replay the flash.
    @Published var flashes: [UInt16: Int] = [:]
    /// The modifiers every layer of this set shares: none in a mode, usually ⌥ for global binds.
    private(set) var base: NSEvent.ModifierFlags = []
    private(set) var chord: NSEvent.ModifierFlags = []
    private(set) var binds: [KeyBinding] = []
    private(set) var gestures: [GestureBind] = []
    private(set) var legends: [UInt16: String] = [:]
    private(set) var keyboardWidth: CGFloat = 940
    /// The trackpad beside the keyboard, or under it when the screen is too narrow.
    private(set) var padBeside = true

    func load(mode: String, binds all: [KeyBinding], chord: NSEvent.ModifierFlags, reason: Reason, room: CGFloat) {
        self.mode = mode
        self.reason = reason
        self.chord = chord
        binds = all.filter { $0.submap == mode && $0.keyCode < 0x1000 }
        // Gestures are usually global, so show them in a mode too.
        let gestureBinds = all.filter { ($0.submap == mode || $0.submap.isEmpty) && $0.keyCode >= 0x1000 }
        let current = Int(WindowManager.shared.menuBarState()?.workspace ?? "") ?? 1
        gestures = gestureBinds.compactMap { GestureBind($0, current: current) }
        let counts = Dictionary(grouping: binds, by: { KeyHelp.mods($0.mods).subtracting(.shift).rawValue }).mapValues(\.count)
        base = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
            .map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
        legends = HelpKeyboard.typedLegends()
        let pad = gestures.isEmpty ? 0 : GesturePad.width + 20
        padBeside = room >= 940 + pad
        keyboardWidth = min(940, max(560, padBeside ? room - pad : room))
    }

    var shiftLayer: Bool { held.contains(.shift) }
    var layerMods: NSEvent.ModifierFlags { shiftLayer ? base.union(.shift) : base }

    /// What each key does in the layer showing.
    var labels: [UInt16: HelpLabel] {
        let mods = layerMods
        var out: [UInt16: HelpLabel] = [:]
        for b in binds where KeyHelp.mods(b.mods) == mods && out[b.keyCode] == nil {
            if let l = HelpLabel(b.dispatcher, b.arg) { out[b.keyCode] = l }
        }
        return out
    }
}

// MARK: - Labels

/// The action groups, each with its colour on the keys.
enum HelpGroup {
    case navigation, workspaces, layout, window, exit

    var color: Color {
        switch self {
        case .navigation: Theme.groupNavigation
        case .workspaces: Theme.groupWorkspaces
        case .layout: Theme.groupLayout
        case .window: Theme.groupWindow
        case .exit: Theme.groupExit
        }
    }
}

/// A short action label for a keycap: an arrow, a workspace number or a word or two.
struct HelpLabel: Equatable {
    let text: String
    let group: HelpGroup

    /// Single glyphs (arrows, numbers) are drawn larger.
    var isGlyph: Bool { text.count <= 2 }

    init(_ text: String, _ group: HelpGroup) { self.text = text; self.group = group }

    init?(_ dispatcher: String, _ rawArg: String) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces).lowercased()
        func arrow(_ d: String) -> String? { ["l": "←", "d": "↓", "u": "↑", "r": "→"][String(d.prefix(1))] }
        func step(_ next: String, _ prev: String) -> String { arg.hasPrefix("-") || arg.hasPrefix("prev") || arg.hasPrefix("e-") ? prev : next }
        switch dispatcher {
        case "movefocus", "swapwindow":
            guard let a = arrow(arg) else { return nil }
            self.init(a, .navigation)
        case "movewindow":
            if arg.hasPrefix("mon:") {
                let rest = String(arg.dropFirst(4))
                self.init(arrow(rest).map { "Screen \($0)" } ?? (rest.hasPrefix("-") ? "‹ Screen" : "Screen ›"), .workspaces)
            } else {
                guard let a = arrow(arg) else { return nil }
                self.init(a, .navigation)
            }
        case "focusmonitor", "movewindowtomonitor":
            self.init(arrow(arg).map { "Screen \($0)" } ?? step("Screen ›", "‹ Screen"), .workspaces)
        case "workspace", "movetoworkspace", "movetoworkspacesilent":
            if let n = Int(arg) { self.init("\(n)", .workspaces) }
            else if arg == "previous" { self.init("Back", .workspaces) }
            else { self.init(step("Next", "Prev"), .workspaces) }
        case "cyclelayout": self.init(step("Layout ›", "‹ Layout"), .layout)
        case "layout", "setlayout": self.init(Layout(rawValue: arg)?.title ?? "Layout", .layout)
        case "splitratio": self.init(arg.hasPrefix("-") ? "Main −" : "Main +", .layout)
        case "layoutmsg":
            switch arg.split(separator: " ").first.map(String.init) ?? "" {
            case "addmaster": self.init("Mains +", .layout)
            case "removemaster": self.init("Mains −", .layout)
            case "mfact": self.init("Main ±", .layout)
            case "orientationnext": self.init("Layout ›", .layout)
            case "orientationprev": self.init("‹ Layout", .layout)
            case "swapwithmaster", "swapnext", "swapprev": self.init("Swap", .window)
            case "focusmaster": self.init("Main", .navigation)
            case "cyclenext", "cycleprev": self.init("Cycle", .window)
            default: return nil
            }
        case "cyclenext": self.init("Cycle", .window)
        case "swapnext": self.init("Swap", .window)
        case "fullscreen": self.init("Full", .window)
        case "togglefloating": self.init("Float", .window)
        case "retile", "reevaluate": self.init("Retile", .window)
        case "toggletiling": self.init("Tiling", .window)
        case "reload": self.init("Reload", .window)
        case "killactive": self.init("Close", .window)
        case "exec": self.init("Run", .window)
        case "sethomespace": self.init("Home", .workspaces)
        case "submap": self.init(arg == "reset" ? "Exit" : rawArg.capitalized, .exit)
        case "exit": self.init("Quit", .exit)
        default: return nil
        }
    }
}

// MARK: - View

struct KeyHelpView: View {
    @ObservedObject var model: KeyHelpModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var keyboardHeight: CGFloat {
        model.keyboardWidth * (MacKeyboard.height + 0.64) / (MacKeyboard.width + 0.64)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.padBeside {
                HStack(alignment: .center, spacing: 20) { keyboard; pad }
            } else {
                VStack(spacing: 14) { keyboard; pad }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .foregroundStyle(Theme.ink)
        .floatingGlass(shape)
        .opacity(model.shown ? 1 : 0)
        .scaleEffect(model.shown || reduceMotion ? 1 : 0.97)
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: Theme.medium), value: model.shown)
        .padding(margin)
        .allowsHitTesting(false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard help")
    }

    private var keyboard: some View {
        HelpKeyboard(labels: model.labels, legends: model.legends, held: model.held, flashes: model.flashes)
            .frame(width: model.keyboardWidth, height: keyboardHeight)
    }

    @ViewBuilder private var pad: some View {
        if !model.gestures.isEmpty { GesturePad(gestures: model.gestures) }
    }

    /// "Window mode", how it's being shown, and which layer the keys show.
    private var header: some View {
        HStack(spacing: 10) {
            Text(model.mode.isEmpty ? "Global" : "\(model.mode.capitalized) mode").font(Theme.heading(15)).oneLine()
            hint.font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted)
            Spacer(minLength: 16)
            layers
        }
        .frame(height: 24)
    }

    @ViewBuilder private var hint: some View {
        switch model.reason {
        case .hold:
            HStack(spacing: 5) {
                Text("shown while you hold").oneLine()
                Kbd(keys: ConfigDocument.modifierCaps(model.chord))
            }
        case .toggle:
            HStack(spacing: 5) {
                Text("press").oneLine()
                Kbd(keys: ["?"])
                Text("to hide").oneLine()
            }
        case .menu:
            Text("click or press any key to close").oneLine()
        }
    }

    /// Keys | ⇧ Keys, following the real ⇧. Not a control: the one accent fill marks the layer showing.
    private var layers: some View {
        let base = ConfigDocument.modifierCaps(model.base).joined()
        let shifted = ConfigDocument.modifierCaps(model.base.union(.shift)).joined()
        return HStack(spacing: 2) {
            segment((base.isEmpty ? "" : base + " ") + "Keys", on: !model.shiftLayer)
            segment(shifted + " Keys", on: model.shiftLayer)
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .fixedSize()
        .animation(Motion.spring, value: model.shiftLayer)
    }

    private func segment(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(Theme.body(12.5, on ? .medium : .regular)).oneLine()
            .foregroundStyle(on ? Theme.onAccent : Theme.inkMuted)
            .padding(.horizontal, 12).frame(height: 22)
            .background { if on { Capsule().fill(Theme.accent) } }
    }
}

// MARK: - Keyboard

/// The keyboard drawing behind one small interface (labels, legends, held modifiers, flashes), so the
/// shared keyboard view from the Shortcut Map can replace it later. Uses `MacKeyboard`'s key geometry.
struct HelpKeyboard: View {
    let labels: [UInt16: HelpLabel]
    /// What each typing key prints on the current layout.
    let legends: [UInt16: String]
    let held: NSEvent.ModifierFlags
    let flashes: [UInt16: Int]

    var body: some View {
        GeometryReader { g in
            let pad: CGFloat = 0.32
            let unit = g.size.width / (MacKeyboard.width + pad * 2)
            ZStack(alignment: .topLeading) {
                ForEach(MacKeyboard.keys) { k in
                    let gap = unit * 0.1
                    HelpKeyCap(key: k, unit: unit, legend: legend(k), label: k.code.flatMap { labels[$0] },
                               held: !k.modifier.isEmpty && held.contains(k.modifier),
                               flash: k.code.flatMap { flashes[$0] } ?? 0)
                        .frame(width: k.frame.width * unit - gap, height: k.frame.height * unit - gap)
                        .offset(x: (pad + k.frame.minX) * unit + gap / 2, y: (pad + k.frame.minY) * unit + gap / 2)
                }
            }
        }
    }

    private func legend(_ k: MacKeyboard.Key) -> String {
        switch k.label {
        case .char(let base, _): k.code.flatMap { legends[$0] } ?? base
        case .word(let w, _): w
        case .function(_, let n): "F\(n)"
        case .modifier(let symbol, _, _): symbol
        case .arrow: ""
        case .globe: "fn"
        case .space, .touchID: ""
        }
    }

    /// The typing keys' legends on the current keyboard layout, letters in capitals.
    static func typedLegends() -> [UInt16: String] {
        var out: [UInt16: String] = [:]
        for k in MacKeyboard.keys {
            guard let code = k.code, case .char = k.label,
                  let base = ConfigDocument.typedCharacter(keyCode: code, flags: []) else { continue }
            out[code] = base.uppercased()
        }
        return out
    }
}

/// One key. Bound keys show their action in the group colour with a ring and a soft glow, and the
/// key's own legend small in the corner; unbound keys recede. Held modifiers get an ink ring.
private struct HelpKeyCap: View {
    let key: MacKeyboard.Key
    let unit: CGFloat
    let legend: String
    let label: HelpLabel?
    let held: Bool
    let flash: Int

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: unit * 0.12, style: .continuous)
        let color = label?.group.color ?? Theme.ink
        ZStack(alignment: .topLeading) {
            shape.fill(Theme.well)
            if let label {
                shape.strokeBorder(color, lineWidth: 1.5)
                if case .arrow = key.label {} else {
                    Text(legend).font(Theme.keys(unit * 0.15, .medium)).foregroundStyle(Theme.inkMuted).oneLine()
                        .padding(.leading, unit * 0.09).padding(.top, unit * 0.06)
                }
                Text(label.text)
                    .font(label.isGlyph ? glyphFont(label.text) : Theme.body(unit * 0.19, .medium))
                    .foregroundStyle(color)
                    .oneLine().minimumScaleFactor(0.6)
                    .padding(.horizontal, unit * 0.05)
                    .padding(.top, key.frame.height < 1 ? 0 : unit * 0.1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                legendView
            }
            if held { shape.strokeBorder(Theme.ink, lineWidth: 1.5) }
        }
        .background {
            // The glow: the ring again, blurred, behind the key so the text casts nothing.
            if label != nil { shape.stroke(color, lineWidth: 2).blur(radius: unit * 0.1).opacity(0.7) }
        }
        .opacity(label != nil || held ? 1 : 0.16)
        .keyframeAnimator(initialValue: Flash(), trigger: flash) { view, f in
            view.overlay(shape.fill(color.opacity(f.fill))).scaleEffect(f.scale)
        } keyframes: { _ in
            KeyframeTrack(\.fill) {
                LinearKeyframe(0.55, duration: 0.04)
                CubicKeyframe(0, duration: 0.32)
            }
            KeyframeTrack(\.scale) {
                LinearKeyframe(0.94, duration: 0.05)
                SpringKeyframe(1, duration: 0.3, spring: Spring(response: 0.25, dampingRatio: 0.6))
            }
        }
        .animation(.easeOut(duration: Theme.fast), value: held)
        .animation(.easeOut(duration: Theme.fast), value: label)
    }

    private struct Flash { var fill = 0.0; var scale: CGFloat = 1 }

    private func glyphFont(_ s: String) -> Font {
        let arrow = "←↓↑→".contains(s)
        let size = unit * (key.frame.height < 1 ? 0.26 : arrow ? 0.34 : 0.32)
        return arrow ? Theme.keys(size, .medium) : Theme.body(size, .medium)
    }

    /// An unbound key's own legend, as printed on the keyboard.
    @ViewBuilder private var legendView: some View {
        switch key.label {
        case .arrow(let symbol):
            Image(systemName: symbol).font(.system(size: unit * 0.13)).foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .touchID, .space:
            EmptyView()
        case .word, .modifier, .globe:
            Text(legend).font(Theme.keys(unit * 0.17)).foregroundStyle(Theme.ink).oneLine()
                .padding(.horizontal, unit * 0.1).padding(.vertical, unit * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        case .char, .function:
            Text(legend).font(Theme.keys(unit * 0.24)).foregroundStyle(Theme.ink).oneLine()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
