import AppKit

extension WindowManager {
    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info("start: trusted=\(Permission.accessibility.isGranted) windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(Screen.all().count)")
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            for delay in [0.3, 1.0, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.observe(app); self?.scheduleRefresh() }
            }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            if let obs = observers[pid] { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode) }
            observers[pid] = nil
            scanner.forget(pid)
            observing.removeValue(forKey: pid)
            windows.values.filter { $0.pid == pid }.forEach { self.forget($0.id) }
            scheduleRefresh()
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.pendingFocus == nil { self?.animator.cancelFocus() }
            self?.requestFocusObservation()
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            scheduleRefresh(after: 0.15)
            if !config.virtualWorkspaces, config.enablesLayoutHUDOnSpaceChange, config.enablesLayoutHUD, let s = currentScreen() {
                HUD.shared.show(state(for: s).layout.title, layout: state(for: s).layout, on: s.ns)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh(after: 0.4) }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() }
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
            self?.onChange?()
            self?.onModeChange?(name)
        }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            if !CursorRefresh.isOurs(e) { self?.mouseMoved() }
        }

        Hotkeys.shared.setBindings(config.bindings)
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
        Hotkeys.shared.handler = { [weak self] b in self?.dispatch(b.dispatcher, b.arg) }
        KeyHelp.shared.install()
        CursorActions.shared.install()
        if !Hotkeys.shared.start() {
            Log.info("start: could not create the keyboard event tap")
            HUD.shared.show("Keybinds unavailable: grant Accessibility", on: nil)
        }
        dockWindowPull.prepare = { [weak self] point in self?.prepareDockPull(at: point) }
        if dockWindowPull.start() { dockArea.refresh() } else { Log.info("Dock window import: mouse event tap unavailable") }

        DistributedNotificationCenter.default().addObserver(forName: ipcNotification, object: nil, queue: .main) { [weak self] n in
            if let cmd = n.object as? String { self?.ipc(cmd) }
        }

        prepareFocusSink()
        HUD.shared.prepare(text: currentWorkspace ?? "1", layout: config.layouts.first)
        requestFocusObservation()
        refresh()
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
        }
    }

    func reload(showHUD: Bool = true) {
        let wasVirtual = config.virtualWorkspaces
        config = Config.load()
        if wasVirtual != config.virtualWorkspaces {
            if wasVirtual { restoreHiddenWindows() }
            model.resetWorkspaces()
            labels = [:]; sortSnapshot = nil; closingNow = []; closingApps = []
            SortPanel.shared.abandon()
            Log.info("workspaces: \(config.virtualWorkspaces ? "Ouch workspaces" : "macOS Spaces")")
        }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
        config.errors.forEach { Log.info("config: \($0)") }
        Hotkeys.shared.setBindings(config.bindings)
        for w in windows.values { w.autoFloating = shouldFloat(w) }
        corrections = [:]
        scheduleRefresh(after: 0)
        refresh()
        guard showHUD else { return }
        HUD.shared.show(config.errors.isEmpty ? "Config reloaded" : "Config: \(config.errors.count) error(s), see Console",
                        on: currentScreen()?.ns)
    }

    func toggleTiling() {
        tilingEnabled.toggle()
        HUD.shared.show(tilingEnabled ? "Tiling on" : "Tiling off", on: currentScreen()?.ns)
        refresh()
    }

}
