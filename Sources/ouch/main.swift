import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let layoutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let tilingItem = NSMenuItem(title: "Tiling Enabled", action: #selector(toggleTiling), keyEquivalent: "")
    private var watchdog: Timer?
    private var wasTrusted = true
    private var hadInputMonitoring = Permissions.inputMonitoringGranted
    private var watchdogTicks = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyDefaults()
        Theme.registerFonts()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Ouch")

        let menu = NSMenu()
        menu.delegate = self
        layoutItem.isEnabled = false
        menu.addItem(layoutItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Next Layout", action: #selector(nextLayout), keyEquivalent: "")
        menu.addItem(withTitle: "Retile", action: #selector(retile), keyEquivalent: "")
        menu.addItem(tilingItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Config File", action: #selector(openConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Keyboard Tour…", action: #selector(startTour), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reload), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Quit Ouch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { if $0.action != #selector(NSApplication.terminate(_:)) { $0.target = self } }
        statusItem.menu = menu

        NSApp.mainMenu = makeMainMenu()
        Updater.shared.start()
        WindowManager.shared.onChange = { [weak self] in self?.updateIcon() }
        let firstRun = UserDefaults.standard.object(forKey: "didSetUpLaunchAtLogin") == nil
        LoginItem.enableOnFirstLaunch()
        Onboarding.shared.statusButton = statusItem.button

        wasTrusted = AXIsProcessTrusted()
        if wasTrusted { WindowManager.shared.start() } else { Log.info("launch: Accessibility not granted") }
        // `open ouch.app --args --onboarding` plays it regardless, for working on it.
        if Onboarding.shouldShow(firstRun: firstRun, trusted: wasTrusted) || CommandLine.arguments.contains("--onboarding") {
            Onboarding.shared.start() // its welcome card asks for Accessibility
        } else if !wasTrusted {
            Permissions.request()
        }
        updateIcon()
        // Permission can be granted later, or silently revoked (a rebuild changes the signature).
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.checkPermission() }
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

    private func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if trusted, !Hotkeys.shared.rawCapsActive { Hotkeys.shared.startRawCaps() }
        let monitoring = Permissions.inputMonitoringGranted
        if monitoring != hadInputMonitoring {
            hadInputMonitoring = monitoring
            Log.info("Input Monitoring \(monitoring ? "granted" : "revoked")")
            if monitoring { PermissionGuide.shared.granted(.inputMonitoring) }
        }
        // Keyboards plugged in later start with macOS's Caps Lock delay again.
        watchdogTicks += 1
        if watchdogTicks % 20 == 0 { Hotkeys.shared.refreshCapsLockDelay() }
        if trusted && !WindowManager.shared.isStarted {
            Log.info("Accessibility granted")
            WindowManager.shared.start()
        } else if trusted && !Hotkeys.shared.isActive {
            Hotkeys.shared.restart()
        }
        if trusted != wasTrusted {
            Log.info("Accessibility \(trusted ? "granted" : "revoked")")
            wasTrusted = trusted
            updateIcon()
            // Revoked (or a rebuild invalidated it): start over so we're listed again.
            if trusted { PermissionGuide.shared.granted() } else { Permissions.reset() }
        }
    }

    /// Opening the app again (Finder, Spotlight, `open`) while it runs shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindow.shared.show(pane: nil)
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        WindowManager.shared.restoreHiddenWindows()
        Hotkeys.shared.restoreCapsLockDelay()
    }

    /// Menu bar indicator, like a Waybar workspaces module: workspaces with windows, the
    /// focused display's one filled in.
    private func updateIcon() {
        // Only checkPermission() updates wasTrusted; doing it here too (window events call this)
        // could swallow a revocation before the watchdog sees it.
        let trusted = AXIsProcessTrusted()
        guard let button = statusItem.button else { return }
        let summary = WindowManager.shared.workspaceSummary()
        guard trusted, !summary.all.isEmpty || !Hotkeys.shared.submap.isEmpty else {
            button.image = NSImage(systemSymbolName: trusted ? "rectangle.split.3x1" : "exclamationmark.triangle",
                                   accessibilityDescription: "Ouch")
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.image = nil
        let title = NSMutableAttributedString()
        if !Hotkeys.shared.submap.isEmpty {
            title.append(NSAttributedString(string: Hotkeys.shared.submap.uppercased() + "  ", attributes: [
                .font: Theme.nsMono(11), .foregroundColor: NSColor.controlAccentColor,
            ]))
        }
        for (i, ws) in summary.all.enumerated() where ws.windows > 0 || ws.shown {
            if title.length > 0 { title.append(NSAttributedString(string: " ")) }
            let current = ws.name == summary.current
            let glyph: String
            if let n = Int(ws.name), (1...10).contains(n) {
                glyph = String(UnicodeScalar((current ? 0x2775 : 0x245F) + UInt32(n))!) // ❶… / ①…
            } else {
                glyph = current ? "[\(ws.name)]" : ws.name
            }
            let color: NSColor = current ? .labelColor : (ws.windows > 0 ? .secondaryLabelColor : .tertiaryLabelColor)
            title.append(NSAttributedString(string: glyph, attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: current ? .bold : .regular), .foregroundColor: color,
                .baselineOffset: 0.5,
            ]))
            _ = i
        }
        button.attributedTitle = title
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.filter { $0.tag == 42 }.forEach(menu.removeItem)
        guard AXIsProcessTrusted() else {
            layoutItem.title = "Needs Accessibility permission"
            return
        }
        // Workspace list, so a workspace can also be picked with the mouse.
        let summary = WindowManager.shared.workspaceSummary()
        var at = 1
        for ws in summary.all where ws.windows > 0 || ws.shown {
            let item = NSMenuItem(title: "Workspace \(ws.name)" + (ws.windows > 0 ? "  (\(ws.windows) window\(ws.windows == 1 ? "" : "s"))" : ""),
                                  action: #selector(pickWorkspace(_:)), keyEquivalent: "")
            item.representedObject = ws.name
            item.state = ws.name == summary.current ? .on : .off
            item.target = self
            item.tag = 42
            menu.insertItem(item, at: at)
            at += 1
        }
        if at > 1 {
            let sep = NSMenuItem.separator()
            sep.tag = 42
            menu.insertItem(sep, at: at)
        }
        layoutItem.title = "Layout: \(WindowManager.shared.currentLayoutTitle)"
        tilingItem.state = WindowManager.shared.tilingEnabled ? .on : .off
    }

    /// Only shown while the settings window is active; without an Edit menu, ⌘C/⌘V/⌘Z don't work in text fields.
    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        let updates = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit Ouch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

    @objc private func checkForUpdates() {
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
    @objc private func openSettings() { SettingsWindow.shared.show(pane: nil) }
    @objc private func startTour() { Onboarding.shared.startTour() }
    @objc private func pickWorkspace(_ sender: NSMenuItem) {
        if let ws = sender.representedObject as? String { WindowManager.shared.showWorkspace(ws) }
    }
    @objc private func nextLayout() { WindowManager.shared.dispatch("cyclelayout", "next") }
    @objc private func retile() { WindowManager.shared.dispatch("retile", "") }
    @objc private func toggleTiling() { WindowManager.shared.toggleTiling() }
    @objc private func reload() { WindowManager.shared.reload() }
    @objc private func openConfig() {
        _ = Config.load() // writes the default file if it's missing
        NSWorkspace.shared.open([Config.url], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
}

// The onboarding tour's practice windows run as a second copy of this binary (see PracticeDesk).
if CommandLine.arguments.dropFirst().first == "practice" {
    PracticeDesk.run(parent: pid_t(CommandLine.arguments.dropFirst(2).first ?? "") ?? getppid())
}

// Command-line mode, like hyprctl: `ouch dispatch movefocus l`, `ouch dump`, `ouch reload`.
let cliArgs = Array(CommandLine.arguments.dropFirst())
if let cmd = cliArgs.first, ["dispatch", "dump", "reload", "poststyle", "grabtest"].contains(cmd) {
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
