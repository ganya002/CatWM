import AppKit
import SwiftUI

private final class SortWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SortHost: NSHostingView<SortView> {
    var sizeChanged: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged?()
    }
}

final class SortPanel: NSObject, NSWindowDelegate {
    static let shared = SortPanel()

    private let wm = WindowManager.shared
    private let model = SortModel()
    private var panel: SortWindow?
    private var host: SortHost?
    private var monitors: [Any] = []
    private var screenObserver: Any?
    private var active = false
    private var fitQueued = false
    private var wasPaused = false
    private var width: CGFloat = 0
    private var anchor = (minY: CGFloat(0), visible: NSRect.zero)
    private var generation = 0
    private var liveWork: DispatchWorkItem?
    private var pruneTimer: Timer?
    private var applyingUntil = Date.distantPast

    private var toast: OverlayPanel?
    private var toastWork: DispatchWorkItem?

    var isOpen: Bool { active }

    func toggle() { isOpen ? finish() : open() }


    func open() {
        guard !isOpen, wm.config.virtualWorkspaces else { return }
        let displays = wm.sortDisplays()
        guard displays.contains(where: { !$0.items.isEmpty }) else {
            HUD.shared.show("No windows to sort", on: nil)
            return
        }
        dismissToast()
        SortNudge.shared.dismiss()
        generation += 1
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let start = displays.first { $0.screen == screen && !$0.items.isEmpty } ?? displays.first { !$0.items.isEmpty } ?? displays[0]
        wm.beginSort()
        model.finish = { [weak self] ws in self?.finish(goTo: ws, focus: true) }
        model.revert = { [weak self] in self?.revert() }
        model.changed = { [weak self] in self?.scheduleLive() }
        active = true
        model.motion = PanelMotion.current
        model.shown = false
        model.begin(displays: displays, start: start.id, config: wm.config)

        let v = screen.visibleFrame
        width = min(1100, v.width - 32)
        let host = SortHost(rootView: SortView(model: model, width: width))
        host.sizingOptions = [.intrinsicContentSize]
        host.sizeChanged = { [weak self] in self?.queueFit() }
        let p = panel ?? makePanel()
        p.ignoresMouseEvents = false
        p.delegate = self
        panel = p
        self.host = host
        p.contentView = host
        host.layoutSubtreeIfNeeded()
        anchor = (v.minY + 18 - SortView.inset.bottom, v)
        p.setFrame(placed(host.fittingSize), display: true)

        wasPaused = Hotkeys.shared.paused
        Hotkeys.shared.paused = true
        if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        installMonitors()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, active else { return }
            model.prune(alive: wm.liveWindowIDs())
        }

        p.alphaValue = 1
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(nil)
        fit()
        PerfMonitor.track("ui:sort-panel", for: 0.5)
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    private func makePanel() -> SortWindow {
        let p = SortWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        return p
    }

    private func placed(_ size: CGSize) -> NSRect {
        let v = anchor.visible
        let w = min(size.width, v.width), h = min(size.height, v.maxY - anchor.minY)
        return NSRect(x: v.midX - w / 2, y: anchor.minY, width: w, height: h)
    }

    private func queueFit() {
        guard !fitQueued else { return }
        fitQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.fitQueued = false
            self?.fit()
        }
    }

    private func fit() {
        guard active, let panel, let host else { return }
        let size = host.fittingSize
        guard size.height > 0 else { return }
        let f = placed(size)
        guard f != panel.frame else { return }
        panel.setFrame(f, display: false)
    }


    func revert() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        wm.revertSort()
    }

    func finish(goTo: String? = nil, focus: Bool = false) {
        guard active else { return }
        flushLive()
        let done = model.result()
        let screen = model.currentDisplay?.screen ?? NSScreen.main
        close()
        wm.finishSort(closing: done.closing, goTo: goTo, focus: focus)
        guard done.changed else { return wm.dropSortSnapshot() }
        showToast("Sorted into \(done.workspaces) workspace\(done.workspaces == 1 ? "" : "s")"
                  + (done.closing.isEmpty ? "" : ", closed \(done.closing.count)"), on: screen)
    }

    func abandon() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        wm.endSort()
    }


    private func scheduleLive() {
        liveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushLive() }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func flushLive() {
        liveWork?.cancel()
        liveWork = nil
        let plans = model.pendingApplies()
        guard active, !plans.isEmpty else { return }
        applyingUntil = Date().addingTimeInterval(1)
        model.markApplied()
        wm.liveSort(plans)
        if let panel, !panel.isKeyWindow { panel.makeKey() }
    }

    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in self?.key(e) == true ? nil : e }) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
            self?.finish()
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] e in
            if let self, e.window !== self.panel { self.finish() }
            return e
        }) { monitors.append(m) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.finish() }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
        screenObserver = nil
    }

    private func teardown() {
        removeMonitors()
        pruneTimer?.invalidate()
        pruneTimer = nil
        guard active else { return }
        active = false
        Hotkeys.shared.paused = wasPaused
        model.end()
    }

    private func close() {
        teardown()
        guard let panel, panel.isVisible else { return }
        panel.delegate = nil
        generation += 1
        let gen = generation
        let done = { [weak self] in
            guard let self, gen == generation else { return }
            panel.orderOut(nil)
            panel.contentView = nil
            panel.alphaValue = 1
            host = nil
        }
        model.shown = false
        panel.ignoresMouseEvents = true
        DispatchQueue.main.asyncAfter(deadline: .now() + model.motion.outDuration + 0.02, execute: done)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard active else { return }
        if Date() < applyingUntil {
            DispatchQueue.main.async { [weak self] in
                guard let self, active, let panel else { return }
                panel.makeKey()
            }
            return
        }
        finish()
    }


    private func key(_ e: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        if panel.firstResponder is NSTextView {
            guard [53, 36, 76].contains(e.keyCode) else { return false }
            panel.makeFirstResponder(nil)
            return true
        }
        let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
        var mods: CGEventFlags = []
        if flags.contains(.command) { mods.insert(.maskCommand) }
        if flags.contains(.option) { mods.insert(.maskAlternate) }
        if flags.contains(.control) { mods.insert(.maskControl) }
        if flags.contains(.shift) { mods.insert(.maskShift) }
        if wm.config.bindings.contains(where: { $0.dispatcher == "sort" && $0.submap.isEmpty && $0.keyCode == e.keyCode && $0.mods == mods }) {
            finish()
            return true
        }
        if flags == .command {
            if e.keyCode == 6 { model.undoRemove() }
            return e.keyCode == 6
        }
        switch e.keyCode {
        case 53: revert(); return true
        case 36, 76: if flags.isEmpty { finish(focus: true); return true }
        default: break
        }
        return model.handle(code: e.keyCode, mods: mods, characters: e.characters ?? "")
    }


    func undoApplied() {
        guard wm.undoSort() else { return }
        let screen = toast?.screen
        dismissToast()
        HUD.shared.show("Sort undone", on: screen)
    }


    private func showToast(_ text: String, on screen: NSScreen?) {
        guard let screen else { return }
        dismissToast()
        let view = SortToastView(text: text, keys: ShortcutIndex().keys("sort-undo")) { [weak self] in self?.undoApplied() }
        let host = FirstClickHostingView(rootView: view)
        let size = host.fittingSize
        let v = screen.visibleFrame
        let p = OverlayPanel(frame: NSRect(x: v.midX - size.width / 2, y: v.minY + 24 - SortToastView.inset.bottom, width: size.width, height: size.height),
                             level: .statusBar, clickThrough: false)
        p.contentView = host
        p.alphaValue = 0
        p.orderFrontRegardless()
        animate(0.28) { p.animator().alphaValue = 1 }
        toast = p
        let work = DispatchWorkItem { [weak self] in self?.dismissToast() }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func dismissToast() {
        toastWork?.cancel()
        toastWork = nil
        guard let p = toast else { return }
        toast = nil
        wm.dropSortSnapshot()
        animate(0.2, changes: { p.animator().alphaValue = 0 }) { p.orderOut(nil) }
    }
}

private struct SortToastView: View {
    let text: String
    let keys: [String]
    let undo: () -> Void
    static let inset = EdgeInsets(top: 20, leading: 40, bottom: 56, trailing: 40)

    var body: some View {
        HStack(spacing: 12) {
            Text(text).font(Theme.body(13.5)).oneLine()
            OButton("Undo", variant: .ghost, shortcut: keys, action: undo)
        }
        .surface(.sm, glass: true)
        .padding(Self.inset)
        .fixedSize()
    }
}
