import AppKit
import Combine
import SwiftUI

/// A key-capable borderless panel that takes the keyboard without activating Ouch.
private final class SortWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Sort Windows: a panel on the display under the pointer that groups a crowded display into workspaces.
/// Every edit is applied to the real windows at once (debounced). Esc reverts to how things were when it
/// opened; ⏎, a click outside or the sort key again keeps the changes and closes the windows marked in
/// Close, and a toast offers Undo.
final class SortPanel: NSObject, NSWindowDelegate {
    static let shared = SortPanel()

    private let wm = WindowManager.shared
    private let model = SortModel()
    private var panel: SortWindow?
    private var host: NSHostingView<SortView>?
    private var monitors: [Any] = []
    private var screenObserver: Any?
    private var active = false
    private var sizeSink: AnyCancellable?
    private var wasPaused = false
    private var width: CGFloat = 0
    /// Where the panel's bottom edge sits and the display it must stay inside, set when it opens.
    private var anchor = (minY: CGFloat(0), visible: NSRect.zero)
    private var generation = 0 // so a fade-out that finishes after a reopen leaves the new panel alone
    private var liveWork: DispatchWorkItem?
    private var pruneTimer: Timer?
    /// Our own live applies can shuffle windows and focus under the panel; until then a resign-key is not the user's doing.
    private var applyingUntil = Date.distantPast

    private var toast: OverlayPanel?
    private var toastWork: DispatchWorkItem?

    var isOpen: Bool { active }

    func toggle() { isOpen ? finish() : open() }

    // MARK: Opening

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
        let host = FirstClickHostingView(rootView: SortView(model: model, width: width))
        let p = panel ?? makePanel()
        p.ignoresMouseEvents = false
        p.delegate = self
        panel = p
        self.host = host
        p.contentView = host
        host.layoutSubtreeIfNeeded()
        anchor = (v.minY + 18 - SortView.inset.bottom, v)
        p.setFrame(placed(host.fittingSize), display: true)
        // The panel follows the content as lanes fill up and empty out, keeping its bottom edge.
        sizeSink = model.$contentSize.removeDuplicates().sink { [weak self] s in self?.fit(to: s) }

        wasPaused = Hotkeys.shared.paused
        Hotkeys.shared.paused = true // keys belong to the panel now
        if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        installMonitors()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, active else { return }
            model.prune(alive: wm.liveWindowIDs())
        }

        p.alphaValue = 1
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(nil)
        fit(to: model.contentSize) // the content may have reported its size before the panel could follow it
        // A turn later, so the view sees `shown` change and plays its entrance.
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    private func makePanel() -> SortWindow {
        let p = SortWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false // drawn by the surface
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        return p
    }

    /// The panel's frame for a content size: centred on its display, bottom edge on the anchor, never taller
    /// or wider than the display so the surface can't end up off screen.
    private func placed(_ size: CGSize) -> NSRect {
        let v = anchor.visible
        let w = min(size.width, v.width), h = min(size.height, v.maxY - anchor.minY)
        return NSRect(x: v.midX - w / 2, y: anchor.minY, width: w, height: h)
    }

    private func fit(to size: CGSize) {
        guard active, let panel, size.height > 0 else { return }
        let f = placed(size)
        guard f != panel.frame else { return }
        panel.setFrame(f, display: true)
    }

    // MARK: Closing

    /// Esc: back to how everything was when the panel opened. Nothing is closed.
    func revert() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        wm.revertSort()
    }

    /// Keeps the changes. Closes the windows marked in Close, then offers Undo; says nothing if nothing changed.
    /// Only a double-clicked workspace or ⏎ may focus a window.
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

    /// The workspace mode changed under the panel: its state is gone, so just let go.
    func abandon() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        wm.endSort()
    }

    // MARK: Live

    private func scheduleLive() {
        liveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushLive() }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Applies whatever was edited since the last time, once.
    private func flushLive() {
        liveWork?.cancel()
        liveWork = nil
        let plans = model.pendingApplies()
        guard active, !plans.isEmpty else { return }
        applyingUntil = Date().addingTimeInterval(1)
        model.markApplied()
        wm.liveSort(plans)
        // Whatever the apply did to focus, the panel keeps the keyboard.
        if let panel, !panel.isKeyWindow { panel.makeKey() }
    }

    /// Clicks in other apps and in our other windows finish it, like a menu; so does a change of displays.
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

    /// Gives the keyboard back and drops the monitors. Safe to run on any close path, any number of times.
    private func teardown() {
        removeMonitors()
        sizeSink = nil
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
        panel.ignoresMouseEvents = true // it's on its way out
        DispatchQueue.main.asyncAfter(deadline: .now() + model.motion.outDuration + 0.02, execute: done)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard active else { return }
        // Our own apply can move focus around; that is never a reason to close. Take the keyboard back.
        if Date() < applyingUntil {
            DispatchQueue.main.async { [weak self] in
                guard let self, active, let panel else { return }
                panel.makeKey()
            }
            return
        }
        finish()
    }

    // MARK: Keys

    private func key(_ e: NSEvent) -> Bool {
        guard let panel, panel.isKeyWindow else { return false }
        // Typing a name: only Esc and Return are ours (they finish the name).
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
        // The key that opened the panel closes it.
        if wm.config.bindings.contains(where: { $0.dispatcher == "sort" && $0.submap.isEmpty && $0.keyCode == e.keyCode && $0.mods == mods }) {
            finish()
            return true
        }
        if flags == .command {
            if e.keyCode == 6 { model.undoRemove() } // ⌘Z
            return e.keyCode == 6
        }
        switch e.keyCode {
        case 53: revert(); return true
        case 36, 76: if flags.isEmpty { finish(focus: true); return true }
        default: break
        }
        return model.handle(code: e.keyCode, mods: mods, characters: e.characters ?? "")
    }

    // MARK: Undo

    /// Puts everything back as it was when the panel opened (the toast's Undo, or the `sort-undo` bind).
    func undoApplied() {
        guard wm.undoSort() else { return }
        let screen = toast?.screen
        dismissToast()
        HUD.shared.show("Sort undone", on: screen)
    }

    // MARK: Toast

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

/// "Sorted into 5 workspaces, closed 2" with Undo: a Surface `sm` on glass.
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
