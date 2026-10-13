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
    private var flashWork: DispatchWorkItem?
    private var dismissMonitor: Any?
    /// The modifiers that entered the current mode (⌘ for ⌘⇪); holding them on keeps the help up.
    private var chordMods: NSEvent.ModifierFlags = []
    private static let margin: CGFloat = 40
    private static let bottomGap: CGFloat = 16
    private static let holdDelay = 0.5

    private var enabled: Bool { WindowManager.shared.config.keyboardHelp }
    var isVisible: Bool { model.shown }

    /// Hooks into the key tap. Called once when the window manager starts.
    func install() {
        Hotkeys.shared.onFlagsChanged = { [weak self] f in self?.flagsChanged(Self.mods(f)) }
        NotificationCenter.default.addObserver(forName: Hotkeys.didFire, object: nil, queue: .main) { [weak self] n in
            if let b = n.userInfo?["bind"] as? KeyBinding { self?.fired(b) }
        }
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
        flashWork?.cancel()
        withAnimation(.easeOut(duration: Theme.fast)) { model.pressed = b.keyCode }
        let work = DispatchWorkItem { [weak self] in withAnimation(.easeOut(duration: Theme.slow)) { self?.model.pressed = nil } }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
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
        // Low on the screen, just above the Dock, so it sits under what you're looking at.
        p.setFrame(CGRect(x: area.midX - size.width / 2, y: area.minY - Self.margin + Self.bottomGap, width: size.width, height: size.height),
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
    /// The key flashing because its shortcut was just pressed.
    @Published var pressed: UInt16?
    /// The modifiers every layer of this set shares: none in a mode, usually ⌥ for global binds.
    private(set) var base: NSEvent.ModifierFlags = []
    private(set) var chord: NSEvent.ModifierFlags = []
    private(set) var binds: [KeyBinding] = []
    private(set) var gestures: [GestureBind] = []
    /// Small enough to stay out of the way; a standard key is still about 38pt.
    static let keyboardMax: CGFloat = 580
    private(set) var keyboardWidth: CGFloat = keyboardMax
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
        let pad = gestures.isEmpty ? 0 : GesturePad.width + 20
        padBeside = room >= Self.keyboardMax + pad
        keyboardWidth = min(Self.keyboardMax, max(440, padBeside ? room - pad : room))
    }

    var shiftLayer: Bool { held.contains(.shift) }
    var layerMods: NSEvent.ModifierFlags { shiftLayer ? base.union(.shift) : base }

    /// What each key does in the layer showing.
    var hints: [KeyHint] {
        let mods = layerMods
        var seen = Set<UInt16>()
        return binds.filter { KeyHelp.mods($0.mods) == mods && seen.insert($0.keyCode).inserted }.map { KeyHint($0) }
    }

    /// Held modifiers, as the key codes that get a ring.
    var hot: Set<UInt16> {
        Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && held.contains($0.modifier) }.compactMap(\.code))
    }
}

// MARK: - View

struct KeyHelpView: View {
    @ObservedObject var model: KeyHelpModel
    let margin: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            header
            if model.padBeside {
                HStack(alignment: .center, spacing: 20) { keyboard; pad }
            } else {
                VStack(spacing: 14) { keyboard; pad }
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
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
        let scale = model.keyboardWidth / KeyHintKeyboard.size(scale: 1).width
        return KeyHintKeyboard(binds: model.hints, style: .labels, pressed: model.pressed, hot: model.hot, scale: scale)
    }

    @ViewBuilder private var pad: some View {
        if !model.gestures.isEmpty { GesturePad(gestures: model.gestures) }
    }

    /// "Window mode", how it's being shown, and which layer the keys show.
    private var header: some View {
        HStack(spacing: 10) {
            Text(model.mode.isEmpty ? "Global" : "\(model.mode.capitalized) mode").font(Theme.heading(13.5)).oneLine()
            hint.font(Theme.body(12)).foregroundStyle(Theme.inkMuted)
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
