import AppKit
import CatWMKit
import SwiftUI

extension SortPanel {
    func toggle() {
        if isOpen {
            finish()
        } else {
            open()
        }
    }

    func open() {
        guard !isOpen, manager.config.virtualWorkspaces, !manager.nativeDesktop.isRunning,
              !manager.desktops.nativeCreationBusy else { return }
        let displays = manager.sortDisplays()
        func hasWindows(_ display: SortDisplay) -> Bool { !display.items.isEmpty || !display.fullscreen.isEmpty }
        guard displays.contains(where: hasWindows) else {
            HUD.shared.show("No windows to show", on: nil)
            return
        }
        guard let screen = CatWMPanel.pointerScreen() else { return }
        dropUndo()
        SortNudge.shared.dismiss()
        generation += 1
        let start = displays.first { $0.screen == screen && hasWindows($0) }
            ?? displays.first(where: hasWindows) ?? displays[0]
        manager.beginSort()
        model.finish = { [weak self] workspace in self?.finish(goTo: workspace, focus: true) }
        model.openFullscreen = { [weak self] id in self?.finish(opening: id) }
        model.revert = { [weak self] in self?.revert() }
        model.changed = { [weak self] in self?.scheduleLive() }
        active = true
        model.motion = PanelMotion.current
        model.shown = false
        model.begin(displays: displays, start: start.id, config: manager.config)

        width = min(1100, screen.visibleFrame.width - 32)
        let host = SortHost(rootView: SortView(model: model, width: width))
        host.sizingOptions = [.intrinsicContentSize]
        host.sizeChanged = { [weak self] in self?.queueFit() }
        let shownPanel = panel ?? makePanel()
        shownPanel.ignoresMouseEvents = false
        shownPanel.delegate = self
        panel = shownPanel
        self.host = host
        shownPanel.contentView = host
        host.layoutSubtreeIfNeeded()
        self.screen = screen
        shownPanel.setFrame(placed(host.fittingSize), display: true)

        wasPaused = Hotkeys.shared.paused
        Hotkeys.shared.paused = true
        if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        installMonitors()
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, active else { return }
            model.prune(alive: manager.liveWindowIDs())
        }

        shownPanel.alphaValue = 1
        shownPanel.makeKeyAndOrderFront(nil)
        shownPanel.makeFirstResponder(nil)
        fit()
        PerfMonitor.shared.track("ui:sort-panel", for: 0.5)
        DispatchQueue.main.async { [weak self] in self?.model.shown = true }
    }

    func makePanel() -> CatWMPanel {
        let menuPanel = CatWMPanel(role: .menu)
        menuPanel.onClose = { [weak self] in self?.revert() }
        return menuPanel
    }

    func placed(_ size: CGSize) -> NSRect {
        guard let screen else { return .zero }
        let frame = CatWMPanel.frame(size: size, on: screen, anchor: .bottom(0))
        return NSRect(x: frame.minX, y: screen.frame.minY, width: frame.width,
                      height: min(size.height, screen.visibleFrame.maxY - screen.frame.minY))
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
        let frame = placed(size)
        if frame != panel.frame { panel.setFrame(frame, display: false) }
        if let screen { showGhosts(on: screen) }
    }

    func showGhosts(on screen: NSScreen) {
        guard ghostPanel?.contentView == nil else { return placeGhosts() }
        let ghosts = ghostPanel ?? CatWMPanel(role: .tooltip)
        ghostPanel = ghosts
        ghosts.contentView = CatWMHostingView(rootView: SortGhosts(model: model))
        ghosts.setFrame(screen.frame, display: false)
        ghosts.orderFrontRegardless()
        placeGhosts()
    }

    func placeGhosts() {
        guard let panel, let screen else { return }
        let shift = CGSize(width: panel.frame.minX - screen.frame.minX, height: screen.frame.maxY - panel.frame.maxY)
        if model.ghostShift != shift { model.ghostShift = shift }
    }

    func revert() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        manager.revertSort()
    }

    func finish(goTo: String? = nil, focus: Bool = false, opening fullscreen: CGWindowID? = nil) {
        guard active else { return }
        flushLive()
        let done = model.result()
        let leaving = model.fullscreenMoves()
        close()
        manager.finishSort(closing: done.closing, goTo: goTo, focus: focus, opening: fullscreen,
                           leavingFullscreen: leaving)
        guard done.changed else { return manager.dropSortSnapshot() }
        keepUndo()
    }

    func abandon() {
        guard active else { return }
        liveWork?.cancel()
        liveWork = nil
        close()
        manager.endSort()
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
        manager.liveSort(plans)
        if let panel, !panel.isKeyWindow { panel.makeKey() }
    }

    func installMonitors() {
        dismiss.start(keeps: { [weak self] in $0 === self?.panel || Popup.shared.owns($0) }, screens: true,
                      key: { [weak self] event in self?.key(event) == true }, close: { [weak self] in self?.finish() })
    }
}
