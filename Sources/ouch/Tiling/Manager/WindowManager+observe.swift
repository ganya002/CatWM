import AppKit

extension WindowManager {

    func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        guard observing[pid] == nil else { return }
        let token = UUID()
        observing[pid] = token
        scanner.run(pid) { [weak self] in
            var observer: AXObserver?
            let created = AXObserverCreate(pid, axCallback, &observer) == .success
            var ok = false
            if created, let observer {
                let element = axApp(pid)
                for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                             kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
                    if AXObserverAddNotification(observer, element, name as CFString, nil) == .success { ok = true }
                }
            }
            let registered = ok ? observer : nil
            DispatchQueue.main.async {
                guard let self, self.observing[pid] == token else { return }
                self.observing[pid] = nil
                guard let registered, NSRunningApplication(processIdentifier: pid) != nil else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registered), .defaultMode)
                self.observers[pid] = registered
                self.windows.values.filter { $0.pid == pid }.forEach(self.watch)
            }
        }
    }

    func watch(_ w: Window) {
        guard let obs = observers[w.pid] else { return }
        scanner.run(w.pid) {
            for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                      kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
                AXObserverAddNotification(obs, w.element, n as CFString, nil)
            }
        }
    }

    func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            lastClose = Date()
            requestFocusObservation()
            scheduleRefresh()
            FocusDim.shared.update()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let w = windows.values.first(where: { CFEqual($0.element, element) }),
                  !animator.isBusy(w.id), !movingToSpace else { return }
            let id = w.id
            observeFrame(w)
            if NSEvent.pressedMouseButtons & 1 != 0 {
                drags[id] = (drags[id] ?? false) || notification == kAXWindowResizedNotification
            } else if !w.isFloating {
                scheduleRefresh(after: 0.25)
            }
        case kAXFocusedWindowChangedNotification:
            observeFocus(element)
            FocusDim.shared.update()
            onChange?()
        case kAXWindowMiniaturizedNotification:
            windowMinimizeChanged(element, minimized: true)
        case kAXWindowDeminiaturizedNotification:
            windowMinimizeChanged(element, minimized: false)
        case kAXWindowCreatedNotification:
            for delay in [0, 0.3, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
            }
        default:
            scheduleRefresh()
        }
    }

    func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, abs(size.width) < 1e5, abs(size.height) < 1e5 else { return }
        let old = minSizes[id] ?? .zero
        let new = CGSize(width: max(old.width, size.width.rounded()), height: max(old.height, size.height.rounded()))
        guard new != old else { return }
        minSizes[id] = new
        corrections[id] = nil
        Log.info("window \(id) has a minimum size of \(Int(new.width))×\(Int(new.height)); re-tiling around it")
        if let r = ratioChange, Date() < r.until {
            ratioChange = nil
            warnTooSmall(id, on: Screen.all().first { $0.uuid == r.screen })
        }
        scheduleRefresh()
    }

    func forget(_ id: CGWindowID) {
        animator.cancel(id)
        templateHiddenWindows[id] = nil
        if !restoringTemplate, focusClock > 0, focusStamps[id] == focusClock { refocusAfterClose = workspaceOf[id] }
        if pendingFocus?.id == id { cancelFocusRequest() }
        if reportedFocus?.id == id {
            reportedFocus = nil
            focusObservation += 1
        }
        windows[id] = nil
        frameReads[id] = nil
        dirtyFrames.remove(id)
        snapNextPlacement.remove(id)
        model.forget(id)
        floatFrames[id] = nil; targets[id] = nil; minSizes[id] = nil; corrections[id] = nil; drags[id] = nil
        displayOf[id] = nil
        closingNow.remove(id)
        visible.remove(id)
    }

    private static let alwaysFloatingApps: Set<String> = [
        "com.apple.installer",
        "com.apple.PackageKit.Install-Progress",
        "com.apple.DiskImageMounter",
        "com.apple.archiveutility",
        "com.apple.MigrateAssistant",
        "com.apple.SoftwareUpdate",
        "com.apple.Stickies",
        "com.apple.PhotoBooth",
        "com.apple.Chess",
        "com.apple.DigitalColorMeter",
        "com.apple.printcenter",
        "com.apple.BluetoothFileExchange",
        "com.apple.ColorSyncUtility",
        "com.apple.Magnifier",
        "com.yourcompany.installerbase",
        "io.balena.etcher",
        "com.wireguard.macos",
        "io.tailscale.ipn.macsys",
        "io.tailscale.ipn.macos",
        "com.jetbrains.toolbox",
        "com.lujjjh.LinearMouse",
        "com.amethyst.Amethyst",
        "org.sparkle-project.Sparkle.Autoupdate",
        "com.microsoft.autoupdate2",
    ]

    private static let signInTitle = try? NSRegularExpression(
        pattern: "^(sign[ -]?in|log[ -]?in)(?=$|[\\s\\-–—|:,])", options: .caseInsensitive)

    private func isUtilityWindow(_ w: Window, title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        if title == "Picture in Picture" || title == "Picture-in-Picture" { return true }
        if w.bundleID == "com.apple.finder" { return title.hasSuffix(" Info") }
        if let re = Self.signInTitle, re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil { return true }
        let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName
        let settings = ["Settings", "Preferences", "Settings…", "Preferences…"]
        return settings.contains(title) || name.map { n in settings.contains { title == "\(n) \($0)" } } == true
    }

    private func isMountedImageWindow(title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.contains { url in
            guard url.path != "/", let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return v.volumeName == title && (v.volumeIsEjectable == true || v.volumeIsInternal == false)
        }
    }

    func shouldFloat(_ w: Window, title known: String?? = nil, resizable: Bool? = nil) -> Bool {
        if let p = practice, w.pid == p.pid { return false }
        if let b = w.bundleID, b == Bundle.main.bundleIdentifier || b.hasPrefix("local.ouch") || b == "local.hyprthyst" {
            return true
        }
        if let b = w.bundleID, Self.alwaysFloatingApps.contains(b) { return true }
        let title = known ?? w.title
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
        if !(resizable ?? w.resizable) { return true }
        let f = w.naturalFrame
        if config.floatSmallWindows, !f.isNull, f.width < 500, f.height < 500 { return true }
        return false
    }
}
