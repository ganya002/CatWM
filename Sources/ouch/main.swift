// App: entry point and AppDelegate (launch, migration from Hyprthyst, CLI subcommands, wiring).
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        closePreviousInstances()
        migrateLegacyDefaults()
        Theme.registerFonts()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Ouch")
        // The menu is Ouch's own (see StatusMenu); it opens on mouse down like a native one.
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleMenu)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        StatusMenu.shared.button = statusItem.button

        NSApp.mainMenu = makeMainMenu()
        Updater.shared.start()
        CrashWatch.start()
        PerfMonitor.start()
        WindowManager.shared.onChange = { [weak self] in
            self?.updateIcon()
            StatusMenu.shared.refreshIfOpen()
        }
        let firstRun = UserDefaults.standard.object(forKey: "didSetUpLaunchAtLogin") == nil
        LoginItem.enableOnFirstLaunch()
        Onboarding.shared.statusButton = statusItem.button

        let watcher = PermissionWatcher.shared
        watcher.start()
        let trusted = watcher.granted.contains(.accessibility)
        if trusted { WindowManager.shared.start() } else { Log.info("launch: Accessibility not granted") }
        // `open ouch.app --args --onboarding` plays it regardless, for working on it.
        if Onboarding.shouldShow(firstRun: firstRun, trusted: trusted) || CommandLine.arguments.contains("--onboarding") {
            Onboarding.shared.start() // its welcome card asks for Accessibility
        } else if !trusted {
            Permission.accessibility.request()
        }
        Tips.shared.launched()
        updateIcon()
        watcher.subscribe { [weak self] granted, changed in self?.permissionsChecked(granted, changed) }
    }

    /// The newest Ouch wins: any other copy (same bundle ID, or same executable for unbundled dev
    /// builds) is asked to quit, then force-quit after a short wait. Waiting matters because the old
    /// copy puts parked windows back on exit, which must finish before this one reads window state.
    private func closePreviousInstances() {
        let me = ProcessInfo.processInfo.processIdentifier
        let myExe = Bundle.main.executableURL?.resolvingSymlinksInPath()
        let others = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != me, !app.isTerminated else { return false }
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
        }
    }

    /// The app used to be called Hyprthyst (bundle ID local.hyprthyst). Copies its saved workspace
    /// assignments, grab hints and update choices once, so the rename doesn't lose them.
    private func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromHyprthyst") else { return }
        d.set(true, forKey: "migratedFromHyprthyst")
        guard let old = d.persistentDomain(forName: "local.hyprthyst") else { return }
        // The login item belongs to the app bundle, so the new app still has to register its own.
        for (key, value) in old where d.object(forKey: key) == nil && !key.hasPrefix("NSWindow Frame") && key != "didSetUpLaunchAtLogin" {
            d.set(value, forKey: key)
        }
        Log.info("migrated \(old.count) settings from Hyprthyst")
    }

    private func permissionsChecked(_ granted: Set<Permission>, _ changed: Set<Permission>) {
        let trusted = granted.contains(.accessibility)
        if changed.contains(.inputMonitoring) {
            let monitoring = granted.contains(.inputMonitoring)
            Log.info("Input Monitoring \(monitoring ? "granted" : "revoked")")
            if monitoring { PermissionGuide.shared.granted(.inputMonitoring) }
        }
        if trusted && !WindowManager.shared.isStarted {
            Log.info("Accessibility granted")
            WindowManager.shared.start()
        } else if trusted && !Hotkeys.shared.isActive {
            Hotkeys.shared.restart()
        }
        if changed.contains(.accessibility) {
            Log.info("Accessibility \(trusted ? "granted" : "revoked")")
            updateIcon()
            // Revoked (or a rebuild invalidated it): start over so we're listed again.
            if trusted { PermissionGuide.shared.granted() } else { Permission.accessibility.reset() }
        }
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show(pane: nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.restoreHiddenWindows()
        CrashWatch.cleanExit()
    }

    /// Menu bar indicator: the focused display's workspace, a drawing of its layout, and the
    /// apps on it.
    private func updateIcon() {
        // A live check, not the watcher's last state: window events call this too, and only the
        // watcher may record a change, or a revocation could be swallowed before it sees it.
        let trusted = Permission.accessibility.isGranted
        guard let button = statusItem.button else { return }
        button.attributedTitle = NSAttributedString(string: "")
        guard trusted, let state = WindowManager.shared.menuBarState() else {
            button.image = NSImage(systemSymbolName: trusted ? "rectangle.split.3x1" : "exclamationmark.triangle",
                                   accessibilityDescription: "Ouch")
            return
        }
        MenuBarIcon.pruneIcons(keeping: Set(state.pids))
        button.image = MenuBarIcon.image(mode: Hotkeys.shared.submap, workspace: state.workspace, layout: state.layout,
                                         pids: state.pids)
    }

    /// Only shown while the settings window is active; without an Edit menu, ⌘C/⌘V/⌘Z don't work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        let updates = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesItem), keyEquivalent: "")
        updates.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Quit Ouch", action: #selector(quitOrCloseWindow), keyEquivalent: "q").target = self
        main.addItem(withTitle: "Ouch", action: nil, keyEquivalent: "").submenu = appMenu
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

    /// Sparkle's check, or a note when this build has no update feed.
    static func checkForUpdates() {
        guard Updater.shared.isConfigured else {
            let a = NSAlert()
            a.messageText = "Updates aren't set up in this build"
            a.informativeText = "This build has no update feed. Release builds check for updates automatically."
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        Updater.shared.checkForUpdates()
    }
    /// ⌘Q in Settings or any Ouch panel with the keyboard closes just that window (an OuchPanel catches it
    /// itself first), and so does it while the key help shows; otherwise it quits.
    @objc private func quitOrCloseWindow() {
        if OuchPanel.closeKeyWindow() { return }
        if KeyHelp.shared.isVisible { KeyHelp.shared.hide() } else { NSApp.terminate(nil) }
    }
    /// ⌘W: the same, but never quits. Borderless panels can't `performClose`, so this doesn't send it to them.
    @objc private func closeWindow() {
        if !OuchPanel.closeKeyWindow() && KeyHelp.shared.isVisible { KeyHelp.shared.hide() }
    }
    @objc private func checkForUpdatesItem() { Self.checkForUpdates() }
    @objc private func toggleMenu() { StatusMenu.shared.toggle() }
}

// The onboarding tour's practice windows run as a second copy of this binary (see PracticeDesk).
if CommandLine.arguments.dropFirst().first == "practice" {
    let args = Array(CommandLine.arguments.dropFirst(2)) // <parent pid> [comma-separated app titles]
    let titles = args.count > 1 ? args[1].split(separator: ",").map(String.init) : []
    PracticeDesk.run(parent: pid_t(args.first ?? "") ?? getppid(), titles: titles)
}

// `ouch docs` prints the folder of agent-readable docs bundled in the app.
if CommandLine.arguments.dropFirst().first == "docs" {
    if let dir = Bundle.main.resourceURL?.appendingPathComponent("AgentDocs"),
       FileManager.default.fileExists(atPath: dir.path) {
        print(dir.path)
        exit(0)
    }
    FileHandle.standardError.write(Data("No bundled docs found\n".utf8))
    exit(1)
}

// Command-line mode, like hyprctl: `ouch dispatch movefocus l`, `ouch dump`, `ouch reload`.
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let cmd = cliArgs.first, ["dispatch", "dump", "reload", "poststyle", "grabtest", "modefx", "panelfx", "intro", "introlab"].contains(cmd) {
    DistributedNotificationCenter.default().postNotificationName(ipcNotification, object: cliArgs.joined(separator: " "),
                                                                 userInfo: nil, deliverImmediately: true)
    if cmd == "dump" { print("State written to \(Log.url.path)") }
    exit(0)
}

// Killed (e.g. by build.sh) or interrupted: put parked windows back before exiting.
var signalSources: [DispatchSourceSignal] = []
for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        WindowManager.shared.restoreHiddenWindows()
        CrashWatch.cleanExit()
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
