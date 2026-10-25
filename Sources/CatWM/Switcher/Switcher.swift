import AppKit
import SwiftUI

enum SwitcherKey: String, CaseIterable {
    case next, prev, peek, app, scope, bring, minimize, close, quit, hide, pick, cancel

    init(_ argument: String) {
        let name = argument.lowercased()
        self = name.hasPrefix("prev") ? .prev : Self(rawValue: name) ?? .next
    }

    var opens: Bool { self == .next || self == .prev }

    var label: String {
        switch self {
        case .next: "Switch"
        case .prev: "‹ Switch"
        case .pick: "Open"
        default: rawValue.capitalized
        }
    }
}

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
    private var binds: [UInt64: KeyBinding] = [:]
    private static let holdDelay = 0.15
    private static let releaseDelay = 0.3

    func install() {
        Hotkeys.shared.intercept = { [weak self] type, event in self?.intercept(type, event) ?? false }
        model.onPick = { [weak self] item in self?.confirm(item) }
        model.onDismiss = { [weak self] in self?.cancel() }
    }

    private func open(backward: Bool) {
        let items = WindowManager.shared.switcherItems()
        guard !items.isEmpty else { return }
        let focused = WindowManager.shared.focusedWindow()?.id
        let start = backward ? items.count - 1 : (items[0].id == focused ? min(1, items.count - 1) : 0)
        let held = CGEventSource.flagsState(.combinedSessionState)
            .intersection([.maskCommand, .maskAlternate, .maskControl])
        guard !held.isEmpty else { WindowManager.shared.switchTo(items[start]); return }
        active = true
        sticky = false
        binds = Dictionary(WindowManager.shared.config.switcherBindings.map { (Hotkeys.key($0.keyCode, $0.mods), $0) },
                           uniquingKeysWith: { first, _ in first })
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

    func run(_ argument: String, isRepeat: Bool = false) {
        let key = SwitcherKey(argument)
        guard active else {
            if key.opens { open(backward: key == .prev) }
            return
        }
        let manager = WindowManager.shared
        switch key {
        case .next, .prev: move(key == .prev ? -1 : 1, wrap: !isRepeat)
        case .peek: togglePeek()
        case .app: model.toggleAppFilter(); reveal()
        case .scope: model.nextScope(); reveal()
        case .bring: bringHere()
        case .minimize: act(wholeApp: false) { manager.minimizeSwitcherItem($0) }
        case .close: act(wholeApp: false) { manager.closeWindow($0.id) }
        case .quit: act(wholeApp: true) { Self.app($0)?.terminate() ?? false }
        case .hide: act(wholeApp: true) { Self.app($0)?.hide() ?? false }
        case .pick: if let item = model.selected { confirm(item) }
        case .cancel: cancel()
        }
    }

    private func key(_ code: UInt16, _ flags: CGEventFlags, isRepeat: Bool) {
        guard active else { return }
        jumpWork?.cancel()
        releaseWork?.cancel()
        let extra = flags.subtracting(holdMods)
        if code == 51 { edit { model.erase(all: !extra.isDisjoint(with: [.maskCommand, .maskAlternate])) }; return }
        let typed = extra.isDisjoint(with: [.maskCommand, .maskControl])
            ? (code == 49 ? " " : ConfigDocument.typedCharacter(keyCode: code, flags: extra.contains(.maskShift)
                ? .shift : [])) : nil
        if model.searching, let typed { edit { model.type(typed) }; return }
        if let bind = binds[Hotkeys.key(code, extra)] ?? binds[Hotkeys.key(code, flags)] {
            if bind.dispatcher == WindowActions.switcher.name, bind.repeats || !isRepeat {
                run(bind.arg, isRepeat: isRepeat)
            }
            return
        }
        if let typed, code != 49 { edit { model.type(typed) } }
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
        let millimeters = screen.displayID.map { CGDisplayScreenSize($0).width } ?? 0
        model.barLimit = millimeters > 0
            ? SwitcherView.Tile.widestMillimeters * screen.frame.width / millimeters : nil
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
