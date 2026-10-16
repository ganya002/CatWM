// Tiling: watches apps and windows through AX notifications and decides which windows float.
import AppKit

extension WindowManager {
    // MARK: - Observing apps

    func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return }
        let el = axApp(pid)
        var ok = false
        for n in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                  kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
            if AXObserverAddNotification(obs, el, n as CFString, nil) == .success { ok = true }
        }
        guard ok else { return } // app not ready yet; we'll retry on the next refresh
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
        // Windows found before the app answered AX had nothing to register with.
        windows.values.filter { $0.pid == pid }.forEach(watch)
    }

    func watch(_ w: Window) {
        guard let obs = observers[w.pid] else { return }
        for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                  kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, w.element, n as CFString, nil)
        }
    }

    func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            lastClose = Date()
            scheduleRefresh()
            FocusDim.shared.update()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            // Look the window up here first: `windowID` asks the app, which may still be busy with our own frames.
            guard let w = windows.values.first(where: { CFEqual($0.element, element) }) ?? element.windowID.flatMap({ windows[$0] }),
                  !animator.isBusy(w.id), !movingToSpace else { return }
            let id = w.id
            if NSEvent.pressedMouseButtons & 1 != 0 {
                drags[id] = (drags[id] ?? false) || notification == kAXWindowResizedNotification
            } else if !w.isFloating {
                scheduleRefresh(after: 0.25) // the app moved itself: put it back in its slot
            }
        case kAXFocusedWindowChangedNotification:
            // A window we haven't seen yet (e.g. minimized or on another Space when we started,
            // now restored): pick it up instead of waiting for some other event.
            if let id = element.windowID, windows[id] == nil { scheduleRefresh(after: 0.1) }
            followFocus()
            FocusDim.shared.update()
            onChange?()
        case kAXWindowCreatedNotification:
            // The window often isn't in the on-screen list yet when this fires, so look again shortly.
            for delay in [0.05, 0.3, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
            }
        default:
            scheduleRefresh()
        }
    }

    func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
        // A size from a window that's going away can be garbage; a minimum must be a real, screen-sized number.
        guard size.width.isFinite, size.height.isFinite, abs(size.width) < 1e5, abs(size.height) < 1e5 else { return }
        let old = minSizes[id] ?? .zero
        let new = CGSize(width: max(old.width, size.width.rounded()), height: max(old.height, size.height.rounded()))
        guard new != old else { return }
        minSizes[id] = new
        corrections[id] = nil
        Log.info("window \(id) has a minimum size of \(Int(new.width))×\(Int(new.height)); re-tiling around it") // finite and small, per the guard above
        if let r = ratioChange, Date() < r.until {
            ratioChange = nil
            warnTooSmall(id, on: Screen.all().first { $0.uuid == r.screen })
        }
        scheduleRefresh()
    }

    func forget(_ id: CGWindowID) {
        if focusClock > 0, focusStamps[id] == focusClock { refocusAfterClose = workspaceOf[id] }
        if pendingFocus?.id == id { pendingFocus = nil }
        windows[id] = nil
        snapNextPlacement.remove(id)
        model.forget(id) // workspace, tiling order and focus history
        floatFrames[id] = nil; targets[id] = nil; minSizes[id] = nil; corrections[id] = nil; drags[id] = nil
        displayOf[id] = nil
        closingNow.remove(id) // macOS reuses window IDs: a new window must not stay hidden for a sort
        visible.remove(id)
    }

    /// Apps whose windows are one-off utilities on macOS (installers, archive and disk tools), so they
    /// float whatever the user's floating list says.
    private static let alwaysFloatingApps: Set<String> = [
        "com.apple.installer",                // .pkg installer
        "com.apple.PackageKit.Install-Progress",
        "com.apple.DiskImageMounter",
        "com.apple.archiveutility",
        "com.apple.MigrateAssistant",
        "com.apple.SoftwareUpdate",
        // Small single-purpose utilities that are meant to sit beside other work.
        "com.apple.Stickies",
        "com.apple.PhotoBooth",
        "com.apple.Chess",
        "com.apple.DigitalColorMeter",
        "com.apple.printcenter",
        "com.apple.BluetoothFileExchange",
        "com.apple.ColorSyncUtility",
        "com.apple.Magnifier",
        // Third-party: installers, updaters and small control panels.
        "com.yourcompany.installerbase",      // Qt Installer Framework maintenance tools
        "io.balena.etcher",
        "com.wireguard.macos",
        "io.tailscale.ipn.macsys",
        "io.tailscale.ipn.macos",
        "com.jetbrains.toolbox",
        "com.lujjjh.LinearMouse",
        "com.amethyst.Amethyst",              // another tiler's settings; it must not be tiled itself
        "org.sparkle-project.Sparkle.Autoupdate",
        "com.microsoft.autoupdate2",
    ]

    /// "Sign in", "Sign-in", "Log in" or "Login" at the start of a title, then the end or a separator, so
    /// "Sign in - Google Accounts" and "Login" match but "login.swift" doesn't.
    private static let signInTitle = try? NSRegularExpression(
        pattern: "^(sign[ -]?in|log[ -]?in)(?=$|[\\s\\-–—|:,])", options: .caseInsensitive)

    /// Utility windows that share an app with tiled ones, recognised by title: a browser's
    /// Picture in Picture player, an app's own Settings window, Finder's Get Info panels and sign-in popups.
    private func isUtilityWindow(_ w: Window, title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        if title == "Picture in Picture" || title == "Picture-in-Picture" { return true }
        if w.bundleID == "com.apple.finder" { return title.hasSuffix(" Info") }
        if let re = Self.signInTitle, re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil { return true }
        let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName
        let settings = ["Settings", "Preferences", "Settings…", "Preferences…"]
        return settings.contains(title) || name.map { n in settings.contains { title == "\(n) \($0)" } } == true
    }

    /// A mounted .dmg opens as a Finder window titled with its volume name ("drag to Applications").
    /// Disk images mount as ejectable volumes, so a Finder window named after one floats.
    private func isMountedImageWindow(title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.contains { url in
            guard url.path != "/", let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return v.volumeName == title && (v.volumeIsEjectable == true || v.volumeIsInternal == false)
        }
    }

    /// `title` and `resizable` are what a scan read off the main thread; when nil they are read here.
    func shouldFloat(_ w: Window, title known: String?? = nil, resizable: Bool? = nil) -> Bool {
        if let p = practice, w.pid == p.pid { return false } // same bundle as us, but these are meant to tile
        // Our own windows (Settings, guides) always float, even when another copy of Ouch
        // (a dev build, or the old Hyprthyst) is the one tiling.
        if let b = w.bundleID, b == Bundle.main.bundleIdentifier || b.hasPrefix("local.ouch") || b == "local.hyprthyst" {
            return true
        }
        if let b = w.bundleID, Self.alwaysFloatingApps.contains(b) { return true }
        let title = known ?? w.element.string(kAXTitleAttribute)
        if w.bundleID == "com.apple.finder", isMountedImageWindow(title: title) { return true }
        if isUtilityWindow(w, title: title) { return true }
        if let b = w.bundleID {
            let listed = config.floating.contains { pattern in
                pattern.hasSuffix("*") ? b.hasPrefix(String(pattern.dropLast())) : b == pattern
            }
            if config.floatingIsBlacklist ? listed : !listed { return true }
        } else if !config.floatingIsBlacklist {
            return true
        }
        if !(resizable ?? w.element.isSettable(kAXSizeAttribute)) { return true } // fixed-size windows can't tile
        let f = w.naturalFrame
        if config.floatSmallWindows, !f.isNull, f.width < 500, f.height < 500 { return true }
        return false
    }
}
