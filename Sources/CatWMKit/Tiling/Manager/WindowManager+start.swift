import AppKit

extension WindowManager {
    package func start() {
        startServices()
        guard config.features.contains(.tiling) else { return Log.info("start: tiling is off in the config") }
        startTiling()
    }

    package func startServices() {
        guard !servicesStarted else { return }
        servicesStarted = true
        if config.features.contains(.socket) { ControlServer.shared.start(path: socketPath) }
        store.watch { [weak self] in self?.apply($0, showHUD: true) }
    }

    package func stopServices() {
        servicesStarted = false
        ControlServer.shared.stop()
        store.stopWatching()
    }

    package func startTiling() {
        guard !isStarted else { return }
        startEngine()
        loadWorkspaces()
        if config.features.contains(.tabGroups) { loadTabs() }
        if config.virtualWorkspaces { DesktopUI.prepare() }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info(
            "start: trusted=\(Permission.accessibility.isGranted) "
                + "windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(backend.screens().count)"
        )
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        observeApplicationNotifications()
        observeSpaceAndScreenNotifications()
        installEventMonitors()
        installInputHandlers()
        watchClaims()

        if !embedded { prepareFocusSink() }
        requestFocusObservation()
        refresh()
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter( // style-ok: apps at login become readable with no event
                deadline: .now() + delay
            ) { [weak self] in self?.scheduleRefresh() }
        }
    }

    package func startEngine() {
        isStarted = true
        startedAt = Date()
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }
        animator.onTopRefused = { [weak self] target, actual in self?.learnMenuBar(target, actual) }
        animator.onLanded = { [weak self] in self?.cursorRefresh.soon() }
    }

    package func watchClaims() {
        scanner.watchClaims { [weak self] in DispatchQueue.main.async { self?.scheduleRefresh() } }
    }

    package func stopTiling(then done: @escaping () -> Void = {}) {
        guard isStarted else { return done() }
        surface.stop()
        nativeGestures.stop()
        dockWindowPull.stop()
        dockArea.stop()
        nativeDesktop.stop()
        for observer in notificationObservers { observer.center.removeObserver(observer.token) }
        notificationObservers = []
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers = [:]
        observing = [:]
        scanner.stopWatchingClaims()
        refreshWork?.cancel()
        refreshWork = nil
        crowdWork?.cancel()
        crowdWork = nil
        isStarted = false
        restoreHiddenWindows { [weak self] in
            self?.windows.keys.forEach { self?.animator.cancel($0) }
            done()
        }
        Log.info("stop: tiling stopped")
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter,
                         _ handler: @escaping (Notification) -> Void) {
        notificationObservers.append((center, center.addObserver(forName: name, object: nil, queue: .main,
                                                                  using: handler)))
    }

    private func observeApplicationNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didLaunchApplicationNotification, in: center) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.applicationLaunched(app)
        }
        observe(NSWorkspace.didTerminateApplicationNotification, in: center) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            applicationTerminated(app.processIdentifier)
        }
        observe(NSWorkspace.willPowerOffNotification, in: center) { [weak self] _ in
            Log.info("recovery: macOS is logging out or shutting down; keeping the state of quitting apps")
            self?.poweringOffAt = Date()
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observe(name, in: center) { [weak self] _ in self?.scheduleRefresh() }
        }
        observe(NSWorkspace.didActivateApplicationNotification, in: center) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let echo = focusRequests.focusEcho, echo.matches(app?.processIdentifier),
               let window = windows[echo.id] {
                focus(window, warp: false)
                return
            }
            if self?.focusRequests.pendingFocus == nil { self?.animator.cancelFocus() }
            self?.requestFocusObservation()
        }
    }

    package func applicationLaunched(_ app: NSRunningApplication) {
        observe(app)
        scheduleRefresh(after: 0)
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter( // style-ok: a new app becomes readable with no event
                deadline: .now() + delay
            ) { [weak self] in
                self?.observe(app)
                self?.scheduleRefresh()
            }
        }
    }

    private func applicationTerminated(_ pid: pid_t) {
        release(pid)
        scheduleRefresh()
    }

    package func releaseClaimedApps() {
        let held = Set(windows.values.map(\.pid)).union(observers.keys).union(observing.keys)
        for pid in held.intersection(scanner.claimed) {
            Log.debug("pid \(pid) is in the scope of another instance; leaving its windows")
            release(pid)
        }
    }

    private func release(_ pid: pid_t) {
        if let obs = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observers[pid] = nil
        scanner.terminated(pid)
        observing.removeValue(forKey: pid)
        windows.values.filter { $0.pid == pid }.forEach { self.forget($0.id, keepRecovery: true) }
        animator.terminated(pid)
        focusRequests.focusReader.terminated(pid)
    }

    private func observeSpaceAndScreenNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, in: center) { [weak self] _ in
            guard let self else { return }
            scheduleRefresh(after: 0.15)
            if !config.virtualWorkspaces, config.enablesLayoutHUDOnSpaceChange, config.enablesLayoutHUD,
               let screen = currentScreen() {
                surface.showHUD(state(for: screen).layout.title, layout: state(for: screen).layout, on: screen.nsScreen)
            }
        }
        observe(NSApplication.didChangeScreenParametersNotification, in: .default) { [weak self] _ in
            self?.scheduleRefresh(after: 0.4)
        }
        observeLock()
    }

    private func observeLock() {
        let leave: (Notification) -> Void = { [weak self] _ in self?.surface.leaveMode() }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(name, in: NSWorkspace.shared.notificationCenter, leave)
        }
        observe(Notification.Name("com.apple.screenIsLocked"), in: DistributedNotificationCenter.default(), leave)
    }

    private func installEventMonitors() {
        let monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
                guard let self, !self.drags.isEmpty else { return }
                self.updateTabDropHint()
            },
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.cancelFocusRequest()
                self?.surface.leaveMode()
            },
            NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                if !CursorRefresh.isOurs(event) { self?.mouseMoved() }
            }
        ]
        eventMonitors += monitors.compactMap(\.self)
    }

    private func installInputHandlers() {
        surface.apply(config)
        surface.start(self)
        nativeGestures.enabled = { [weak self] in
            guard let self else { return false }
            return self.config.virtualWorkspaces && !self.surface.keysPaused && !self.closeAndSort.sortSession
                && !self.desktops.nativeCreationBusy
        }
        nativeGestures.receive = { [weak self] in self?.handleNativeSwipe($0) }
        nativeGestures.interrupted = { [weak self] in self?.nativeDesktop.endGesture(commit: false) }
        dockWindowPull.prepare = { [weak self] point in self?.prepareDockPull(at: point) }
        startMouseTaps(logFailure: true)
    }

    package func reload(showHUD: Bool = true) {
        apply(store.reload(.all), showHUD: showHUD)
    }

    package func applyStoredConfig() {
        apply(store.reload(.changed), showHUD: false)
    }

    package func apply(_ next: Config, showHUD: Bool) {
        let old = config
        config = Self.effective(next, scope: scope)
        let changes = config.changes(from: old)
        guard !changes.isEmpty || config.diagnostics != old.diagnostics else { return }
        if changes.contains("features") { applyFeatures(from: old.features) }
        applyWorkspaceChanges(changes, wasVirtual: old.virtualWorkspaces)
        Log.verbose = config.debugLogging || Log.verboseLaunch
        if !changes.isDisjoint(with: Self.surfaceFields) { surface.apply(config) }
        if !changes.isDisjoint(with: Self.floatFields) {
            for window in windows.values { window.autoFloating = shouldFloat(window) }
        }
        if isStarted, !changes.subtracting(Self.liveFields).isEmpty {
            corrections = [:]
            scheduleRefresh(after: 0)
            refresh()
        }
        if !changes.isEmpty { Log.info("config: applied \(changes.sorted().joined(separator: ", "))") }
        config.errors.forEach { Log.info("config: \($0)") }
        EventBus.shared.emit("config.reloaded", ["errors": .array(config.diagnostics.map(\.json))])
        guard showHUD else { return }
        surface.showHUD(
            config.errors.isEmpty ? "Config reloaded" : "Config: \(config.errors.count) error(s), see Console",
            on: currentScreen()?.nsScreen
        )
    }

    private func applyFeatures(from old: Set<Feature>) {
        let features = config.features
        let changed = features.symmetricDifference(old)
        if servicesStarted, changed.contains(.socket) {
            if features.contains(.socket) {
                ControlServer.shared.start(path: socketPath)
            } else {
                ControlServer.shared.stop()
            }
        }
        if servicesStarted, changed.contains(.tiling) {
            if !features.contains(.tiling) { stopTiling() } else if mayTile() { startTiling() }
            return
        }
        guard isStarted else { return }
        applyInputFeatures(changed)
        if changed.contains(.tabStrips) { surface.tabsDidChange(instant: true) }
        if changed.contains(.tabGroups), !features.contains(.tabGroups) { dissolveTabs() }
    }

    private func applyInputFeatures(_ changed: Set<Feature>) {
        let features = config.features
        if changed.contains(.keys) { surface.setKeyBinds(enabled: features.contains(.keys)) }
        if !features.contains(.mouse) {
            dockWindowPull.stop()
            dockArea.stop()
        }
        if !features.contains(.gestures) { nativeGestures.stop() }
        startMouseTaps()
    }

    private func applyWorkspaceChanges(_ changes: Set<String>, wasVirtual: Bool) {
        if changes.contains("virtual-workspaces") {
            nativeDesktop.stop()
            tilingRecovery = TilingRecovery()
            if wasVirtual { restoreHiddenWindows() }
            model.resetWorkspaces()
            labels = [:]; closeAndSort.sortSnapshot = nil; closeAndSort.closingNow = []; closeAndSort.closingApps = []
            surface.abandonOverview()
            Log.info("workspaces: \(config.virtualWorkspaces ? "CatWM workspaces" : "macOS Spaces")")
        } else if changes.contains("workspaces-per-display") {
            nativeDesktop.stop()
            renumberWorkspaces()
        }
    }

    package static let surfaceFields: Set<String> = [
        "bindings", "mod", "virtual-workspaces", "mode-effect", "keyboard-finish", "tab-notification-badges",
        "dim-other-windows", "dim-strength", "blur-other-windows", "blur-radius"
    ]
    package static let floatFields: Set<String> = ["floating", "floating-is-blacklist", "float-small-windows"]
    package static let liveFields: Set<String> = surfaceFields.subtracting(["virtual-workspaces"]).union([
        "features", "mouse-follows-focus", "focus-follows-mouse", "focus-follows-mouse-in-mode-only",
        "mouse-swaps-windows", "mouse-resizes-windows", "enables-layout-hud", "enables-layout-hud-on-space-change",
        "keyboard-help", "keyboard-help-key", "cursor-actions", "template-app-scripting", "switcher-instant-jump",
        "switcher-jump-delay", "switcher-exclude", "animate", "animation-duration", "animation-curve",
        "animation-bounce", "panel-animation", "debug-logging", "perf-reports", "sort-nudge", "window-resize-step",
        "stay-on-workspace-after-close", "remove-empty-workspaces"
    ])

    package func toggleTiling() {
        tilingEnabled.toggle()
        surface.showHUD(tilingEnabled ? "Tiling on" : "Tiling off", on: currentScreen()?.nsScreen)
        refresh()
    }

    package func modeChanged(_ name: String) {
        notifyChange()
        onModeChange?(name)
    }
}

extension WindowManager {
    package func startMouseTaps(logFailure: Bool = false) {
        guard input.mouseTaps else { return }
        if config.features.contains(.gestures) { nativeGestures.start() }
        guard config.features.contains(.mouse), !dockWindowPull.isInstalled else { return }
        if dockWindowPull.start() {
            dockArea.start()
        } else if logFailure {
            Log.info("Dock window import: mouse event tap unavailable")
        }
    }

    package func setInputTaps(enabled: Bool) {
        surface.setKeyTap(enabled: enabled)
        dockWindowPull.setEnabled(enabled)
        nativeGestures.setEnabled(enabled)
        Log.info("input taps \(enabled ? "on" : "off")")
    }
}
