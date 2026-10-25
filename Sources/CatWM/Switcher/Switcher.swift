import AppKit
import SwiftUI

final class Switcher {
    static let shared = Switcher()

    let model = SwitcherModel()
    private var panel: CatWMPanel?
    private var active = false
    private var sticky = false
    private var revealed = false
    private var holdMods: CGEventFlags = []
    private var showWork: DispatchWorkItem?
    private var jumpWork: DispatchWorkItem?
    private var orderOutWork: DispatchWorkItem?
    private var releaseWork: DispatchWorkItem?
    private var clickMonitor: Any?
    private var previewTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private static let holdDelay = 0.15
    private static let releaseDelay = 0.3

    func install() {
        Hotkeys.shared.intercept = { [weak self] type, event in self?.intercept(type, event) ?? false }
        model.onPick = { [weak self] item in self?.confirm(item) }
        model.onDismiss = { [weak self] in self?.cancel() }
    }

    func open(backward: Bool) {
        guard !active else { move(backward ? -1 : 1, wrap: true); return }
        let items = WindowManager.shared.switcherItems()
        guard !items.isEmpty else { return }
        let focused = WindowManager.shared.focusedWindow()?.id
        let start = backward ? items.count - 1 : (items[0].id == focused ? min(1, items.count - 1) : 0)
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskControl])
        guard !held.isEmpty else { WindowManager.shared.switchTo(items[start]); return }
        active = true
        sticky = false
        holdMods = held
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.begin(items, selection: start, displays: NSScreen.screens.count,
                        previews: ScreenRecording.shared.isGranted)
        }
        previewTask = SwitcherPreviews.capture(items.map(\.id), pixels: SwitcherPreviews.thumbPixels) { [weak self] in
            self?.model.setPreview($1, for: $0)
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if CGEventSource.flagsState(.combinedSessionState).contains(holdMods) { reveal() } else { released() }
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDelay, execute: work)
    }

    private func intercept(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard active, event.getIntegerValueField(.eventSourceUserData) != Hotkeys.syntheticMarker else { return false }
        if type == .flagsChanged {
            let lifted = !event.flags.contains(holdMods)
            DispatchQueue.main.async { [weak self] in
                if lifted { self?.released() } else { self?.releaseWork?.cancel() }
            }
            return false
        }
        if !sticky, !event.flags.contains(holdMods) {
            DispatchQueue.main.async { [weak self] in self?.released() }
            return false
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags, isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        DispatchQueue.main.async { [weak self] in self?.key(code, flags, isRepeat: isRepeat) }
        return true
    }

    private func released() {
        guard active else { return }
        guard sticky else { confirmSelection(); return }
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.confirmSelection() }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.releaseDelay, execute: work)
    }

    private func confirmSelection() {
        if let item = model.selected { confirm(item) } else { cancel() }
    }

    private func key(_ code: UInt16, _ flags: CGEventFlags, isRepeat: Bool) {
        guard active else { return }
        jumpWork?.cancel()
        releaseWork?.cancel()
        let command = flags.contains(.maskCommand), extra = flags.subtracting(holdMods)
        switch code {
        case 48: move(flags.contains(.maskShift) ? -1 : 1, wrap: !isRepeat)
        case 124, 125: move(1, wrap: !isRepeat)
        case 123, 126: move(-1, wrap: !isRepeat)
        case 53 where !isRepeat: cancel()
        case 36, 76: if !isRepeat, let item = model.selected { confirm(item) }
        case 51: edit { model.erase(all: !extra.isDisjoint(with: [.maskCommand, .maskAlternate])) }
        case 50: if !isRepeat { model.toggleAppFilter(); reveal() }
        case 49 where !model.query.isEmpty: edit { model.type(" ") }
        case 49: if !isRepeat { togglePeek() }
        default:
            if command, commandKey(code, isRepeat: isRepeat) { return }
            if extra.isDisjoint(with: [.maskCommand, .maskControl]),
                      let text = ConfigDocument.typedCharacter(keyCode: code, flags: extra.contains(.maskShift)
                          ? .shift : []) {
                edit { model.type(text) }
            }
        }
    }

    private func commandKey(_ code: UInt16, isRepeat: Bool) -> Bool {
        guard [1, 4, 11, 12, 13, 46].contains(code) else { return false }
        guard !isRepeat else { return true }
        let manager = WindowManager.shared
        switch code {
        case 1: model.nextScope(); reveal()
        case 11: bringHere()
        case 46: act(wholeApp: false) { manager.minimizeSwitcherItem($0) }
        case 13: act(wholeApp: false) { manager.closeWindow($0.id) }
        case 12: act(wholeApp: true) { Self.app($0)?.terminate() ?? false }
        default: act(wholeApp: true) { Self.app($0)?.hide() ?? false }
        }
        return true
    }

    private func move(_ delta: Int, wrap: Bool) {
        model.move(delta, wrap: wrap)
        reveal()
        if model.peeking { capturePeek() }
    }

    private func togglePeek() {
        guard model.previewing else { return }
        model.peeking.toggle()
        reveal()
        if model.peeking { capturePeek() }
    }

    private func capturePeek() {
        guard let id = model.selected?.id else { return }
        peekTask?.cancel()
        peekTask = SwitcherPreviews.capture([id], pixels: SwitcherPreviews.peekPixels) { [weak self] in
            self?.model.setPreview($1, for: $0)
        }
    }

    private func bringHere() {
        guard let item = model.selected else { return }
        cancel()
        if !WindowManager.shared.bringSwitcherItemHere(item) { WindowManager.shared.switchTo(item) }
    }

    private func edit(_ change: () -> Void) {
        change()
        sticky = sticky || !model.query.isEmpty
        if sticky { reveal() }
        armJump()
    }

    private static func app(_ item: SwitcherItem) -> NSRunningApplication? {
        NSRunningApplication(processIdentifier: item.pid)
    }

    private func act(wholeApp: Bool, _ run: (SwitcherItem) -> Bool) {
        guard let item = model.selected, run(item) else { return }
        model.remove { wholeApp ? $0.pid == item.pid : $0.id == item.id }
        if model.items.isEmpty { cancel() }
    }

    private func armJump() {
        let config = WindowManager.shared.config
        guard config.switcherInstantJump, let target = SwitcherSearch.soleJump(model.pool, query: model.query) else {
            return
        }
        guard config.switcherJumpDelay > 0 else { confirm(target); return }
        let query = model.query
        let work = DispatchWorkItem { [weak self] in
            guard let self, active, model.query == query else { return }
            confirm(target)
        }
        jumpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(config.switcherJumpDelay) / 1000, execute: work)
    }

    private func confirm(_ item: SwitcherItem) {
        guard active else { return }
        cancel()
        WindowManager.shared.switchTo(item)
    }

    private func cancel() {
        guard active else { return }
        active = false
        showWork?.cancel()
        jumpWork?.cancel()
        releaseWork?.cancel()
        previewTask?.cancel()
        peekTask?.cancel()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        guard revealed else { return }
        revealed = false
        model.shown = false
        panel?.ignoresMouseEvents = true
        guard WindowManager.shared.config.animate else { panel?.orderOut(nil); return }
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil) }
        orderOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.fast + 0.05, execute: work)
    }

    private func reveal() {
        showWork?.cancel()
        guard active, !revealed else { return }
        revealed = true
        orderOutWork?.cancel()
        let shown = panel ?? makePanel()
        panel = shown
        layout()
        shown.ignoresMouseEvents = false
        shown.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in if self?.active == true { self?.model.shown = true } }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.cancel()
        }
    }

    private func layout() {
        guard let panel, let screen = WindowManager.shared.focusedScreen ?? CatWMPanel.pointerScreen() else { return }
        let visible = screen.visibleFrame
        panel.place(size: visible.size, on: screen, anchor: .origin(visible.origin))
    }

    private func makePanel() -> CatWMPanel {
        let panel = CatWMPanel(role: .menu)
        let host = NSHostingView(rootView: SwitcherView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}
