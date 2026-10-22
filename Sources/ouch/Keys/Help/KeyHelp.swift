import AppKit
import SwiftUI

final class KeyHelp {
    static let shared = KeyHelp()

    private let model = KeyHelpModel()
    private var panel: OuchPanel?
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
        withAnimation(.easeOut(duration: Theme.fast)) { model.pressed = bind.keyCode }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: Theme.slow)) { self?.model.pressed = nil }
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func show(mode: String, reason: KeyHelpModel.Reason) {
        orderOutWork?.cancel()
        guard let screen = WindowManager.shared.focusedScreen ?? OuchPanel.pointerScreen() else { return }
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

    private func makePanel() -> OuchPanel { OuchPanel(role: .hud) }

    static func mods(_ flags: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)).intersection([.command, .option, .control, .shift])
    }
}
