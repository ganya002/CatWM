// Keys: the on-screen keyboard help overlay.
import AppKit
import SwiftUI

/// On-screen keyboard help: the whole keyboard with every action written on its key, shown only on
/// request. In a mode it appears when you keep holding the chord's modifier (⌘ for ⌘⇪) for half a
/// second after entering, and goes when you let go (the mode's keys work under it as if the modifier
/// were up); `?` in the mode toggles it; the menu bar's
/// Keyboard Help shows it until the next click or key. A click-through, non-activating panel centred
/// on the screen with the focused window. `keyboard-help = false` in the config turns it off.
final class KeyHelp {
    static let shared = KeyHelp()

    private let model = KeyHelpModel()
    private var panel: OuchPanel?
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

    /// The menu bar's Keyboard Help.
    /// If it momentarily exits a mode while opening, fall back to the configured window mode.
    func showFromMenu(preferredMode: String? = nil) {
        holdWork?.cancel()
        let active = Hotkeys.shared.submap
        let mode = active.isEmpty ? (preferredMode ?? "") : active
        show(mode: mode, reason: .menu)
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
        let screen = WindowManager.shared.focusedScreen ?? OuchPanel.pointerScreen()
        let wasShown = model.shown
        Tips.shared.markSeen(.keyHelp)
        model.load(mode: mode, binds: WindowManager.shared.config.bindings, chord: chordMods, reason: reason,
                   room: screen.visibleFrame.width - Self.margin * 2 - 48)
        model.held = Self.mods(CGEventSource.flagsState(.combinedSessionState))

        let p = panel ?? makePanel()
        panel = p
        if !wasShown {
            // A fresh view each time it comes up, built hidden. A reused one would be ordered front showing
            // whatever it drew last (a frame from partway through the way out), then jump before animating.
            model.motion = PanelMotion.current
            let h = NSHostingView(rootView: KeyHelpView(model: model, margin: Self.margin))
            h.sizingOptions = [.intrinsicContentSize] // measured by fittingSize; only setFrame below moves the panel
            host = h
            p.contentView = h
        }
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        // Low on the screen, just above the Dock, so it sits under what you're looking at. Kept on the screen.
        p.place(size: host.fittingSize, on: screen, anchor: .bottom(Self.bottomGap - Self.margin), inset: EdgeInsets(all: Self.margin))
        p.orderFrontRegardless()
        // A turn later, so the view sees `shown` change and fades and scales in.
        if !wasShown { DispatchQueue.main.async { [weak self] in self?.model.shown = true } }

        setDismissMonitor(reason == .menu)
        Hotkeys.shared.heldChord = reason == .hold ? CGEventFlags(rawValue: UInt64(chordMods.rawValue)) : []
    }

    func hide() {
        holdWork?.cancel()
        setDismissMonitor(false)
        Hotkeys.shared.heldChord = []
        guard model.shown else { return }
        model.shown = false
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
            self?.panel?.contentView = nil
            self?.host = nil
        }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(Theme.medium, model.motion.outDuration) + 0.05, execute: work)
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

    private func makePanel() -> OuchPanel { OuchPanel(role: .hud) }

    static func mods(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(f.rawValue)).intersection([.command, .option, .control, .shift])
    }
}

// MARK: - Model

final class KeyHelpModel: ObservableObject {
    enum Reason { case hold, toggle, menu }

    @Published var shown = false
    /// How it comes and goes, fixed while it's up.
    var motion = PanelMotion.current
    @Published var mode = ""
    @Published var reason: Reason = .hold
    /// Modifiers held right now; ⇧ picks the layer and held keys get a ring.
    @Published var held: NSEvent.ModifierFlags = []
    /// The key flashing because its shortcut was just pressed.
    @Published var pressed: UInt16?
    /// The modifiers every layer of this set shares: none in a mode, usually ⌥ for global binds.
    private(set) var base: NSEvent.ModifierFlags = []
    private(set) var binds: [KeyBinding] = []
    /// Small enough to stay out of the way; a standard key is still about 38pt.
    static let keyboardMax: CGFloat = 580
    private(set) var keyboardWidth: CGFloat = keyboardMax

    func load(mode: String, binds all: [KeyBinding], chord: NSEvent.ModifierFlags, reason: Reason, room: CGFloat) {
        self.mode = mode
        self.reason = reason
        binds = all.filter { $0.submap == mode && $0.keyCode < 0x1000 }
        let counts = Dictionary(grouping: binds, by: { KeyHelp.mods($0.mods).subtracting(.shift).rawValue }).mapValues(\.count)
        base = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
            .map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
        keyboardWidth = min(Self.keyboardMax, max(440, room))
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

    var body: some View {
        // Nothing of Ouch's own around it: the SDK keyboard, with its deck, is the whole panel.
        keyboard
            .panelEntrance(model.shown, style: model.motion, radius: 20)
            .padding(margin)
            .allowsHitTesting(false)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Keyboard help")
    }

    private var keyboard: some View {
        let scale = model.keyboardWidth / KeyHintKeyboard.size(scale: 1).width
        return KeyHintKeyboard(binds: model.hints, pressed: model.pressed, hot: model.hot, scale: scale)
            .environment(\.keyTile, model.motion == .tile ? model.shown : nil)
    }
}
