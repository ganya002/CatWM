import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusUpdatePending = false

    func applicationDidFinishLaunching(_: Notification) {
        closePreviousInstances()
        Theme.registerFonts()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "CatWM")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        StatusMenu.shared.button = statusItem.button

        NSApp.mainMenu = makeMainMenu()
        Updater.shared.start()
        CrashWatch.start()
        PerfMonitor.shared.start()
        WindowManager.shared.surface = AppSurface()
        WindowManager.shared.onChange = { [weak self] in
            self?.scheduleStatusUpdate()
        }
        let firstRun = UserDefaults.standard.object(forKey: DefaultsKey.didSetUpLaunchAtLogin) == nil
        LoginItem.shared.enableOnFirstLaunch()
        CommandLineTool.install()
        Onboarding.shared.statusButton = statusItem.button

        let watcher = PermissionWatcher.shared
        watcher.start()
        let trusted = watcher.granted.contains(.accessibility)
        if trusted {
            WindowManager.shared.start()
        } else {
            Log.info("launch: Accessibility not granted")
            WindowManager.shared.prewarm()
        }
        if Onboarding.shouldShow(firstRun: firstRun, trusted: trusted)
            || LaunchFlag.onboarding.isSet {
            Onboarding.shared.start()
        } else if !trusted {
            Permission.accessibility.request()
        }
        Tips.shared.launched()
        WhatsNew.shared.launched()
        #if DEBUG
        if LaunchFlag.gallery.isSet { DesignGallery.shared.open() }
        #endif
        updateIcon()
        watcher.subscribe { [weak self] granted, changed in self?.permissionsChecked(granted, changed) }
    }

    private func closePreviousInstances() {
        let ownPid = ProcessInfo.processInfo.processIdentifier
        let myExe = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != ownPid, !app.isTerminated else { return false }
            if let id = Bundle.main.bundleIdentifier, app.bundleIdentifier == id { return true }
            return myExe != nil && app.executableURL?.resolvingSymlinksInPath() == myExe
        }
        guard !others.isEmpty else { return }
        Log.info("launch: closing \(others.count) previous instance(s)")
        others.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        for app in others where !app.isTerminated {
            Log.info("launch: force-quitting previous instance \(app.processIdentifier)")
            app.forceTerminate()
            CrashWatch.cleanExit()
        }
    }

    private func permissionsChecked(_ granted: Set<Permission>, _ changed: Set<Permission>) {
        let trusted = granted.contains(.accessibility)
        let optional: [Permission] = [.inputMonitoring, .screenRecording, .fullDiskAccess]
        for permission in optional where changed.contains(permission) {
            let isGranted = granted.contains(permission)
            Log.info("\(permission.title) \(isGranted ? "granted" : "revoked")")
            if isGranted { PermissionGuide.shared.granted(permission) }
        }
        if changed.contains(.fullDiskAccess) { Notifications.shared.refreshSources() }
        let manager = WindowManager.shared
        if trusted && !manager.isStarted {
            Log.info("Accessibility granted")
            manager.start()
        } else if trusted {
            if !Hotkeys.shared.isActive { Hotkeys.shared.restart() }
            manager.startMouseTaps()
        }
        if changed.contains(.accessibility) {
            Log.info("Accessibility \(trusted ? "granted" : "revoked")")
            if manager.isStarted {
                manager.setInputTaps(enabled: trusted)
                if !trusted { HUD.shared.show("Keybinds off: Accessibility was turned off", on: nil) }
            }
            updateIcon()
            if trusted { PermissionGuide.shared.granted(.accessibility) } else { Permission.accessibility.reset() }
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        SettingsWindow.shared.show(pane: nil)
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let manager = WindowManager.shared
        Hotkeys.shared.paused = true
        manager.nativeDesktop.stop()
        Task { @MainActor in
            _ = await poll(2, every: 10_000_000) { !manager.nativeDesktop.isRunning }
            manager.isStarted = false
            manager.restoreHiddenWindows { sender.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_: Notification) {
        CrashWatch.cleanExit()
    }

    private func scheduleStatusUpdate() {
        guard !statusUpdatePending else { return }
        statusUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.statusUpdatePending = false
            self.updateIcon()
            StatusMenu.shared.refreshIfOpen()
        }
    }

    private func updateIcon() {
        let trusted = Permission.accessibility.isGranted
        guard let button = statusItem?.button else { return }
        button.attributedTitle = NSAttributedString(string: "")
        guard trusted, let state = WindowManager.shared.menuBarState() else {
            button.image = NSImage(systemSymbolName: trusted ? "rectangle.split.3x1" : "exclamationmark.triangle",
                                   accessibilityDescription: "CatWM")
            return
        }
        AppIcons.shared.prune(keeping: Set(state.pids))
        button.image = MenuBarIcon.image(mode: Hotkeys.shared.submap, workspace: state.workspace, layout: state.layout,
                                         pids: state.pids)
    }

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        let updates = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesItem),
                                      keyEquivalent: "")
        updates.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Quit CatWM", action: #selector(quitOrCloseWindow), keyEquivalent: "q").target = self
        main.addItem(withTitle: "CatWM", action: nil, keyEquivalent: "").submenu = appMenu
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        return main
    }

    static func checkForUpdates() {
        guard Updater.shared.isConfigured else {
            let alert = NSAlert()
            alert.messageText = "Updates aren't set up in this build"
            alert.informativeText = "This build has no update feed. Release builds check for updates automatically."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkForUpdates()
    }
    @objc private func quitOrCloseWindow() {
        if CatWMPanel.closeKeyWindow() { return }
        if KeyHelp.shared.isVisible { KeyHelp.shared.hide() } else { NSApp.terminate(nil) }
    }
    @objc private func closeWindow() {
        if !CatWMPanel.closeKeyWindow() && KeyHelp.shared.isVisible { KeyHelp.shared.hide() }
    }
    @objc private func checkForUpdatesItem() { Self.checkForUpdates() }
    @objc private func toggleMenu() { StatusMenu.shared.toggle() }
}
