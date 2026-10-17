import AppKit
import SwiftUI

extension SortPanel {
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
        host.sizingOptions = [.intrinsicContentSize]
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

    func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        p.onClose = { [weak self] in self?.revert() }
        return p
    }

    func placed(_ size: CGSize) -> NSRect {
        guard let screen else { return .zero }
        return OuchPanel.frame(size: size, on: screen, anchor: .bottom(18 - SortView.inset.bottom),
                               inset: EdgeInsets(top: 0, leading: 0, bottom: SortView.inset.bottom, trailing: 0))
    }

    func queueFit() {
        guard !fitQueued else { return }
        fitQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.fitQueued = false
            self?.fit()
        }
    }

    func fit() {
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

    func scheduleLive() {
        liveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushLive() }
        liveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func flushLive() {
        liveWork?.cancel()
        liveWork = nil
        let plans = model.pendingApplies()
        guard active, !plans.isEmpty else { return }
        applyingUntil = Date().addingTimeInterval(1)
        model.markApplied()
        wm.liveSort(plans)
        if let panel, !panel.isKeyWindow { panel.makeKey() }
    }

    func installMonitors() {
        dismiss.start(keeps: { [weak self] in $0 === self?.panel }, screens: true,
                      key: { [weak self] e in self?.key(e) == true }, close: { [weak self] in self?.finish() })
    }

}
