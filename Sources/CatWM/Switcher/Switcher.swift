import AppKit
import CatWMKit
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
    private static let holdDelay = 0.15
    private static let releaseDelay = 0.3
    private static let rowKeys: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]

    func install() {
        Hotkeys.shared.intercept = { [weak self] type, event in self?.intercept(type, event) ?? false }
        model.onPick = { [weak self] item in self?.confirm(item) }
    }

    func open(backward: Bool) {
        guard !active else { move(backward ? -1 : 1); return }
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
        model.begin(items, selection: start)
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
        case 48: move(flags.contains(.maskShift) ? -1 : 1)
        case 125: move(1)
        case 126: move(-1)
        case 53 where !isRepeat: cancel()
        case 36, 76: if !isRepeat, let item = model.selected { confirm(item) }
        case 51: edit { model.erase(all: !extra.isDisjoint(with: [.maskCommand, .maskAlternate])) }
        case 50: if !isRepeat { model.toggleAppFilter(); reveal() }
        case 49 where !model.query.isEmpty: edit { model.type(" ") }
        case 13 where command: if !isRepeat { act(wholeApp: false) { WindowManager.shared.closeWindow($0.id) } }
        case 12 where command:
            if !isRepeat { act(wholeApp: true) { Self.app($0)?.terminate() ?? false } }
        case 4 where command:
            if !isRepeat { act(wholeApp: true) { Self.app($0)?.hide() ?? false } }
        default:
            if command, let row = Self.rowKeys[code] {
                if !isRepeat, model.results.indices.contains(row) { confirm(model.results[row]) }
            } else if extra.isDisjoint(with: [.maskCommand, .maskControl]),
                      let text = ConfigDocument.typedCharacter(keyCode: code, flags: extra.contains(.maskShift)
                          ? .shift : []) {
                edit { model.type(text) }
            }
        }
        layout()
    }

    private func move(_ delta: Int) {
        model.move(delta)
        reveal()
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
        guard config.switcherInstantJump, let target = SwitcherSearch.soleJump(model.scope, query: model.query) else {
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
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        guard revealed else { return }
        revealed = false
        model.shown = false
        panel?.ignoresMouseEvents = true
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
        guard let panel, active,
              let screen = WindowManager.shared.focusedScreen ?? CatWMPanel.pointerScreen() else { return }
        let size = SwitcherView.size(rows: model.results.count)
        let tallest = CatWMPanel.frame(size: SwitcherView.size(rows: SwitcherView.visibleRows), on: screen,
                                      anchor: .center(dy: screen.visibleFrame.height / 10))
        panel.place(size: size, on: screen, anchor: .origin(NSPoint(x: tallest.minX, y: tallest.maxY - size.height)))
    }

    private func makePanel() -> CatWMPanel {
        let panel = CatWMPanel(role: .menu)
        let host = NSHostingView(rootView: SwitcherView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }
}
