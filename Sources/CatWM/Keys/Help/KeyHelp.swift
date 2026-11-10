import AppKit
import CatWMKit
import SwiftUI

final class KeyHelp {
    static let shared = KeyHelp()

    private let model = KeyHelpModel()
    private var panel: CatWMPanel?
    private var host: NSHostingView<KeyHelpView>?
    private var holdWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?
    private var dismissMonitor: Any?
    private var fireObserver: NSObjectProtocol?
    private var chordMods: NSEvent.ModifierFlags = []
    private static let margin: CGFloat = 40
    private static let bottomGap: CGFloat = 16
    private static let holdDelay = 0.5

    private var enabled: Bool { WindowManager.shared.config.keyboardHelp }
    var isVisible: Bool { model.shown }

    func install() {
        Hotkeys.shared.onFlagsChanged = { [weak self] flags in self?.flagsChanged(Self.mods(flags)) }
        fireObserver = NotificationCenter.default.addObserver(
            forName: Hotkeys.didFire, object: nil, queue: .main
        ) { [weak self] note in
            if let bind = note.userInfo?["bind"] as? KeyBinding { self?.fired(bind) }
        }
        Hotkeys.shared.onHelpKey = { [weak self] in self?.toggle() }
    }

    func modeChanged(_ name: String) {
        holdWork?.cancel()
        guard !name.isEmpty else {
            if model.shown && model.reason != .menu { hide() }
            return
        }
        if model.shown {
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

    func toggle() {
        let mode = Hotkeys.shared.submap
        if model.shown { hide(); return }
        guard enabled, !mode.isEmpty else { return }
        holdWork?.cancel()
        show(mode: mode, reason: .toggle)
    }

    func showFromMenu(preferredMode: String? = nil) {
        holdWork?.cancel()
        let active = Hotkeys.shared.submap
        let mode = active.isEmpty ? (preferredMode ?? "") : active
        show(mode: mode, reason: .menu)
    }

    private func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        if holdWork != nil, !flags.isSuperset(of: chordMods) { holdWork?.cancel(); holdWork = nil }
        guard model.shown else { return }
        if model.reason == .hold, !flags.isSuperset(of: chordMods) { hide(); return }
        if model.held != flags { model.held = flags }
    }

    private func fired(_ bind: KeyBinding) {
        guard model.shown, bind.submap == model.mode, bind.keyCode < 0x1000 else { return }
        flashWork?.cancel()
        withAnimation(Motion.fade) { model.pressed = bind.keyCode }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(Motion.fadeSlow) { self?.model.pressed = nil }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func show(mode: String, reason: KeyHelpModel.Reason) {
        orderOutWork?.cancel()
        guard let screen = WindowManager.shared.focusedScreen ?? CatWMPanel.pointerScreen() else { return }
        let wasShown = model.shown
        Tips.shared.markSeen(.keyHelp)
        model.load(mode: mode, binds: WindowManager.shared.config.bindings, chord: chordMods, reason: reason,
                   room: screen.visibleFrame.width - Self.margin * 2 - 48)
        model.held = Self.mods(CGEventSource.flagsState(.combinedSessionState))

        let helpPanel = panel ?? makePanel()
        panel = helpPanel
        if !wasShown {
            model.motion = PanelMotion.current
            let newHost = NSHostingView(rootView: KeyHelpView(model: model, margin: Self.margin))
            newHost.sizingOptions = [.intrinsicContentSize]
            host = newHost
            helpPanel.contentView = newHost
        }
        guard let host else { return }
        host.layoutSubtreeIfNeeded()
        helpPanel.place(size: host.fittingSize, on: screen, anchor: .bottom(Self.bottomGap - Self.margin),
                        inset: EdgeInsets(all: Self.margin))
        helpPanel.orderFrontRegardless()
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
        let delay = max(Theme.medium, model.motion.outDuration) + 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func setDismissMonitor(_ active: Bool) {
        if let dismissMonitor { NSEvent.removeMonitor(dismissMonitor); self.dismissMonitor = nil }
        guard active else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, model.shown, model.reason == .menu, dismissMonitor == nil else { return }
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
            dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
                self?.hide()
            }
        }
    }

    private func makePanel() -> CatWMPanel { CatWMPanel(role: .hud) }

    static func mods(_ flags: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection([.command, .option, .control, .shift])
    }
}

final class KeyHelpModel: ObservableObject {
    enum Reason { case hold, toggle, menu }

    @Published var shown = false
    var motion = PanelMotion.current
    @Published var mode = ""
    @Published var reason: Reason = .hold
    @Published var held: NSEvent.ModifierFlags = []
    @Published var pressed: UInt16?
    private(set) var base: NSEvent.ModifierFlags = []
    private(set) var binds: [KeyBinding] = []
    static let keyboardMax: CGFloat = 580
    private(set) var keyboardWidth: CGFloat = keyboardMax

    func load(mode: String, binds all: [KeyBinding], chord _: NSEvent.ModifierFlags, reason: Reason, room: CGFloat) {
        self.mode = mode
        self.reason = reason
        binds = all.filter { $0.submap == mode && $0.keyCode < 0x1000 }
        let counts = Dictionary(grouping: binds, by: { KeyHelp.mods($0.mods).subtracting(.shift).rawValue })
            .mapValues(\.count)
        base = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }
            .map { NSEvent.ModifierFlags(rawValue: $0.key) } ?? []
        keyboardWidth = min(Self.keyboardMax, max(440, room))
    }

    var shiftLayer: Bool { held.contains(.shift) }
    var layerMods: NSEvent.ModifierFlags { shiftLayer ? base.union(.shift) : base }

    var hints: [KeyHint] {
        let mods = layerMods
        var seen = Set<UInt16>()
        return binds.filter { KeyHelp.mods($0.mods) == mods && seen.insert($0.keyCode).inserted }.map { KeyHint($0) }
    }

    var hot: Set<UInt16> {
        Set(KeyHintKeyboard.keys.filter { !$0.modifier.isEmpty && held.contains($0.modifier) }.compactMap(\.code))
    }
}

struct KeyHelpView: View {
    @ObservedObject var model: KeyHelpModel
    let margin: CGFloat

    var body: some View {
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
            .environment(\.keyTile, model.motion == .tile ? .tile(shown: model.shown) : .rise)
    }
}
