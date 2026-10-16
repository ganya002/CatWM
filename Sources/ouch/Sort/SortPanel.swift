// Sort: the Sort Windows panel window, its host and the undo toast.
import AppKit
import SwiftUI

/// The Sort view's host: says when the content's size changes so the panel can follow it.
private final class SortHost: OuchHostingView<SortView> {
    var sizeChanged: (() -> Void)?
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        sizeChanged?()
    }
}

/// Sort Windows: a panel on the display under the pointer that groups a crowded display into workspaces.
/// Every edit is applied to the real windows at once (debounced). Esc reverts to how things were when it
/// opened; ⏎, a click outside or the sort key again keeps the changes and closes the windows marked in
/// Close, and a toast offers Undo.
final class SortPanel: NSObject, NSWindowDelegate {
    static let shared = SortPanel()

    private let wm = WindowManager.shared
    private let model = SortModel()
    private var panel: OuchPanel?
    private var host: SortHost?
    private let dismiss = DismissMonitor()
    private var active = false
    private var fitQueued = false
    private var wasPaused = false
    private var width: CGFloat = 0
    /// The display the panel must stay inside, set when it opens.
    private var screen: NSScreen?
    private var generation = 0 // so a fade-out that finishes after a reopen leaves the new panel alone
    private var liveWork: DispatchWorkItem?
    private var pruneTimer: Timer?
    /// Our own live applies can shuffle windows and focus under the panel; until then a resign-key is not the user's doing.
    private var applyingUntil = Date.distantPast

    private var toast: OuchPanel?
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
        let screen = OuchPanel.pointerScreen()
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
        // Measured by fittingSize; placed() moves the panel. With the default options the host resizes the
        // window itself, from its top-left corner, and pushes the panel off the right and bottom of the screen.
        host.sizingOptions = [.intrinsicContentSize]
        // The panel follows the content as lanes fill up and empty out, keeping its bottom edge.
        host.sizeChanged = { [weak self] in self?.queueFit() }
        let p = panel ?? makePanel()
        p.ignoresMouseEvents = false
        p.delegate = self
        panel = p
        self.host = host
        p.contentView = host
        host.layoutSubtreeIfNeeded()
        self.screen = screen
        p.setFrame(placed(host.fittingSize), display: true)

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
        fit() // the content may have changed size before the panel could follow it
        // A turn later, so the view sees `shown` change and plays its entrance.
        PerfMonitor.track("ui:sort-panel", for: 0.5)
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    private func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        // Esc is the key monitor's; ⌘W and ⌘Q revert like it, and never quit Ouch.
        p.onClose = { [weak self] in self?.revert() }
        return p
    }

    /// The panel's frame for a content size: centred on its display, bottom edge just above the Dock, never
    /// taller or wider than the display so the surface can't end up off screen. Only the shadow room under
    /// the surface may hang past the visible area.
    private func placed(_ size: CGSize) -> NSRect {
        guard let screen else { return .zero }
        return OuchPanel.frame(size: size, on: screen, anchor: .bottom(18 - SortView.inset.bottom),
                               inset: EdgeInsets(top: 0, leading: 0, bottom: SortView.inset.bottom, trailing: 0))
    }

    /// Once per turn, after SwiftUI has finished the update that changed the size.
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
        panel.setFrame(f, display: false) // SwiftUI redraws on its own; a forced draw mid-entrance costs a frame
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
        dismiss.start(keeps: { [weak self] in $0 === self?.panel }, screens: true,
                      key: { [weak self] e in self?.key(e) == true }, close: { [weak self] in self?.finish() })
    }

    /// Gives the keyboard back and drops the monitors. Safe to run on any close path, any number of times.
    private func teardown() {
        dismiss.stop()
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
        let host = OuchHostingView(rootView: view)
        let p = OuchPanel(role: .overlay(.statusBar, clickThrough: false),
                          frame: OuchPanel.frame(size: host.fittingSize, on: screen, anchor: .bottom(24 - SortToastView.inset.bottom),
                                                 inset: SortToastView.inset))
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
