import AppKit

extension WindowManager {
    struct PendingLaunch {
        let bundleID: String
        let before: Set<CGWindowID>
        let request: LaunchRequest
        let source: String?
        let until: Date
    }

    func launchCommand(_ arg: String) {
        guard let request = LaunchRequest(arg), let target = Launcher.resolve(request.target) else {
            Log.info("launch: cannot open \(arg)")
            return
        }
        if request.placesWindow, let bundleID = Launcher.bundleID(for: target) {
            let before = Set(TemplateRestorer.windowList(.optionAll).map(\.id))
            pendingLaunches.removeAll { $0.until < Date() }
            pendingLaunches.append(.init(bundleID: bundleID, before: before, request: request,
                                         source: currentScreen()?.uuid, until: Date().addingTimeInterval(15)))
        }
        Task { @MainActor in
            if await !Launcher.open(target) { Log.info("launch: \(request.target) did not open") }
        }
    }

    func claimLaunch(_ window: Window) {
        pendingLaunches.removeAll { $0.until < Date() }
        guard let index = pendingLaunches.firstIndex(where: {
            $0.bundleID == window.bundleID && !$0.before.contains(window.id)
        }) else { return }
        let launch = pendingLaunches.remove(at: index)
        if launch.request.frame != nil { window.userFloating = .chosen(true) }
        Log.info("launch: placing window \(window.id) of \(launch.bundleID)")
        DispatchQueue.main.async { [weak self] in self?.place(window, launch) }
    }

    private func place(_ window: Window, _ launch: PendingLaunch) {
        let screens = Screen.all()
        let origin = screens.first { $0.uuid == launch.source } ?? currentScreen()
        let display = launch.request.display.flatMap { spec in
            origin.flatMap { screen(from: $0, spec: spec, in: screens) }
        }
        if let unit = launch.request.frame,
           let target = display ?? screen(of: window, in: screens) ?? origin {
            let visible = target.visible
            let frame = CGRect(x: visible.minX + unit.minX * visible.width,
                               y: visible.minY + unit.minY * visible.height,
                               width: unit.width * visible.width, height: unit.height * visible.height).integral
            window.naturalFrame = frame
            animator.animate([.init(window: window, to: frame, bounds: visible)],
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
        }
        if let display {
            assignManagedWindow(window.id, to: shown[display.uuid])
            refresh()
        }
        if let raw = launch.request.workspace, let workspace = resolveWorkspace(raw) {
            moveWindow(window, toWorkspace: workspace, follow: false)
        }
    }
}
