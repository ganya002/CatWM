import AppKit

extension WindowManager {
    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        loadTabs()
        if config.virtualWorkspaces { DesktopUI.prepare() }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info(
            "start: trusted=\(Permission.accessibility.isGranted) "
                + "windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(Screen.all().count)"
        )
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }
        animator.onTopRefused = { [weak self] target, actual in self?.learnMenuBar(target, actual) }

        observeApplicationNotifications()
        observeSpaceAndScreenNotifications()
        installEventMonitors()
        installInputHandlers()

        ControlServer.shared.start()

        prepareFocusSink()
        HUD.shared.prepare(text: currentWorkspace ?? "1", layout: config.layouts.first)
        requestFocusObservation()
        refresh()
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
        }
    }

    private func observeApplicationNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.applicationLaunched(app)
        })
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            applicationTerminated(app.processIdentifier)
        })
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleRefresh()
            })
        }
        notificationObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let echo = focusEcho, echo.matches(app?.processIdentifier), let window = windows[echo.id] {
                focus(window, warp: false)
                return
            }
            if self?.pendingFocus == nil { self?.animator.cancelFocus() }
            self?.requestFocusObservation()
        })
    }

    func applicationLaunched(_ app: NSRunningApplication) {
        observe(app)
        scheduleRefresh(after: 0)
        for delay in [0.3, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.observe(app)
                self?.scheduleRefresh()
            }
        }
    }

    private func applicationTerminated(_ pid: pid_t) {
        if let obs = observers[pid] {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        }
        observers[pid] = nil
        scanner.terminated(pid)
        observing.removeValue(forKey: pid)
        windows.values.filter { $0.pid == pid }.forEach { self.forget($0.id) }
        animator.terminated(pid)
        focusReader.terminated(pid)
        scheduleRefresh()
    }

    private func observeSpaceAndScreenNotifications() {
        notificationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            scheduleRefresh(after: 0.15)
            if !config.virtualWorkspaces, config.enablesLayoutHUDOnSpaceChange, config.enablesLayoutHUD,
               let screen = currentScreen() {
                HUD.shared.show(state(for: screen).layout.title, layout: state(for: screen).layout, on: screen.nsScreen)
            }
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleRefresh(after: 0.4) })
        observeLock()
    }

    private func observeLock() {
        let leave: (Notification) -> Void = { _ in
            if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        }
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            notificationObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main, using: leave))
        }
        notificationObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: leave))
    }

    private func installEventMonitors() {
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            guard let self, !self.drags.isEmpty else { return }
            self.updateTabDropHint()
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.cancelFocusRequest()
            if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        }
        Hotkeys.shared.onSubmapChange = { [weak self] name in
            Log.debug("mode: \(name.isEmpty ? "reset" : name)")
            ModeFX.shared.setActive(!name.isEmpty)
            ModeCursor.shared.setActive(!name.isEmpty)
            KeyHelp.shared.modeChanged(name)
            CursorActions.shared.modeChanged(name)
            Tips.shared.modeChanged(name)
            self?.notifyChange()
            self?.onModeChange?(name)
        }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            if !CursorRefresh.isOurs(event) { self?.mouseMoved() }
        }
    }

    private func installInputHandlers() {
        Hotkeys.shared.setBindings(config.workspaceBindings)
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
        Hotkeys.shared.handler = { [weak self] binding in self?.dispatch(binding.dispatcher, binding.arg) }
        KeyHelp.shared.install()
        CursorActions.shared.install()
        Switcher.shared.install()
        nativeGestures.enabled = { [weak self] in
            guard let self else { return false }
            return self.config.virtualWorkspaces && !Hotkeys.shared.paused && !self.sortSession
                && !self.nativeCreationBusy
        }
        nativeGestures.receive = { [weak self] in self?.handleNativeSwipe($0) }
        nativeGestures.interrupted = { [weak self] in self?.nativeDesktop.endGesture(commit: false) }
        startKeyboardTap()
        dockWindowPull.prepare = { [weak self] point in self?.prepareDockPull(at: point) }
        startMouseTaps(logFailure: true)
    }

    func reload(showHUD: Bool = true) {
        nativeDesktop.stop()
        let wasVirtual = config.virtualWorkspaces
        let wasPerDisplay = config.workspacesPerDisplay
        config = Config.load()
        if wasVirtual != config.virtualWorkspaces {
            tilingRecovery = TilingRecovery()
            if wasVirtual { restoreHiddenWindows() }
            model.resetWorkspaces()
            labels = [:]; sortSnapshot = nil; closingNow = []; closingApps = []
            SortPanel.shared.abandon()
            Log.info("workspaces: \(config.virtualWorkspaces ? "Ouch workspaces" : "macOS Spaces")")
        } else if wasPerDisplay != config.workspacesPerDisplay {
            renumberWorkspaces()
        }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
        config.errors.forEach { Log.info("config: \($0)") }
        Hotkeys.shared.setBindings(config.workspaceBindings)
        for window in windows.values { window.autoFloating = shouldFloat(window) }
        corrections = [:]
        scheduleRefresh(after: 0)
        refresh()
        EventBus.shared.emit("config.reloaded", ["errors": .array(config.errors.map(JSON.string))])
        guard showHUD else { return }
        HUD.shared.show(
            config.errors.isEmpty ? "Config reloaded" : "Config: \(config.errors.count) error(s), see Console",
            on: currentScreen()?.nsScreen
        )
    }

    func toggleTiling() {
        tilingEnabled.toggle()
        HUD.shared.show(tilingEnabled ? "Tiling on" : "Tiling off", on: currentScreen()?.nsScreen)
        refresh()
    }
}
