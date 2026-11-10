import AppKit

extension WindowManager {
    package func observe(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        observe(pid: app.processIdentifier)
    }

    package func observe(pid: pid_t) {
        guard isStarted, pid != getpid(), observers[pid] == nil, scanner.keeps(pid) else { return }
        guard observing[pid] == nil else { return }
        let token = UUID()
        observing[pid] = token
        scanner.run(pid) { [weak self] in
            var observer: AXObserver?
            let created = AXObserverCreate(pid, axCallback, &observer) == .success
            var added = false
            if created, let observer {
                let element = axApp(pid)
                for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                             kAXApplicationHiddenNotification, kAXApplicationShownNotification]
                where AXObserverAddNotification(observer, element, name as CFString, nil) == .success {
                    added = true
                }
            }
            let registered = added ? observer : nil
            DispatchQueue.main.async {
                guard let self, self.isStarted, self.observing[pid] == token else { return }
                self.observing[pid] = nil
                guard let registered, self.backend.isRunning(pid) else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(registered), .defaultMode)
                self.observers[pid] = registered
                self.windows.values.filter { $0.pid == pid }.forEach(self.watch)
            }
        }
    }

    package func watch(_ window: Window) {
        guard let obs = observers[window.pid] else { return }
        scanner.run(window.pid) {
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification,
                         kAXWindowResizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(obs, window.element, name as CFString, nil)
            }
        }
    }

    package func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            closeAndSort.lastClose = Date()
            requestFocusObservation()
            scheduleRefresh()
            surface.focusChanged()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let window = windows.values.first(where: { CFEqual($0.element, element) }),
                  !animator.isBusy(window.id), !desktops.movingToSpace, window.id != tabUI.drag.lifted else { return }
            let id = window.id
            observeFrame(window)
            if NSEvent.pressedMouseButtons & 1 != 0 {
                if drags.isEmpty { tabUI.drag.beginNative(id) }
                drags[id] = (drags[id] ?? false) || notification == kAXWindowResizedNotification
            } else if !window.isFloating {
                if notification == kAXWindowResizedNotification {
                    adoptNativeZoom(window)
                } else {
                    scheduleRefresh(after: 0.25)
                }
            }
        case kAXFocusedWindowChangedNotification:
            observeFocus(element)
            surface.focusChanged()
            notifyChange()
        case kAXTitleChangedNotification:
            titleChanged(element)
        case kAXWindowMiniaturizedNotification:
            windowMinimizeChanged(element, minimized: true)
        case kAXWindowDeminiaturizedNotification:
            windowMinimizeChanged(element, minimized: false)
        case kAXWindowCreatedNotification:
            scheduleRefresh(after: 0)
            for delay in [0.3, 1.0] {
                DispatchQueue.main.asyncAfter( // style-ok: a new window becomes readable with no event
                    deadline: .now() + delay
                ) { [weak self] in
                    self?.scheduleRefresh(after: 0)
                }
            }
        default:
            scheduleRefresh()
        }
    }

    package func learnMenuBar(_ target: CGRect, _ actual: CGRect) {
        guard let screen = screen(containing: target) else { return }
        let height = actual.minY - screen.frame.minY
        guard height > 0, height <= 60,
              height > menuBarHeights[screen.uuid]?.height(on: screen.visible) ?? 0 else { return }
        menuBarHeights[screen.uuid] = MenuBarFloor(height: height, visible: screen.visible)
        Log.info("\(screen.name) keeps windows \(Int(height)) pt below its top; tiling below it")
        corrections = [:]
        refresh()
    }

    package func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, abs(size.width) < 1e5, abs(size.height) < 1e5 else { return }
        let old = minSizes[id] ?? .zero
        let new = CGSize(width: max(old.width, size.width.rounded()), height: max(old.height, size.height.rounded()))
        guard new != old else { return }
        minSizes[id] = new
        corrections[id] = nil
        Log.info("window \(id) has a minimum size of \(Int(new.width))×\(Int(new.height)); re-tiling around it")
        if let change = dividerState.ratioChange, Date() < change.until {
            dividerState.ratioChange = nil
            warnTooSmall(id, on: backend.screens().first { $0.uuid == change.screen })
        }
        if let drag = dividerState.dividerDrag, let position = drag.position,
           let screen = backend.screens().first(where: { $0.uuid == drag.screen }) {
            moveDivider(on: screen, to: position)
        }
        scheduleRefresh()
    }

    package func forget(_ id: CGWindowID, keepRecovery: Bool = false) {
        if !keepRecovery, let window = windows[id] { tilingRecovery.forget(recoveryIdentity(window)) }
        animator.forget(id)
        placementHolds.forget(id)
        let focused = focusClock > 0 && focusStamps[id] == focusClock
        showHeir(of: id, focused: focused)
        if focusRequests.forget(id, refocusOn: !restoringTemplate && focused ? workspaceOf[id] : nil) {
            animator.cancelFocus()
        }
        windows[id] = nil
        surface.windowForgotten(id)
        frameReads[id] = nil
        dirtyFrames.remove(id)
        snapNextPlacement.remove(id)
        model.forget(id)
        floats.floatFrames[id] = nil; floats.floatZoom[id] = nil; targets[id] = nil; minSizes[id] = nil
        corrections[id] = nil; drags[id] = nil
        displayOf[id] = nil
        nativeMoves.forget(id)
        closeAndSort.closingNow.remove(id)
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
        "com.microsoft.autoupdate2"
    ]

    private static let signInTitle = try? NSRegularExpression(
        pattern: "^(sign[ -]?in|log[ -]?in)(?=$|[\\s\\-–—|:,])", options: .caseInsensitive)

    private func isUtilityWindow(_ window: Window, title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        if title == "Picture in Picture" || title == "Picture-in-Picture" { return true }
        if window.bundleID == "com.apple.finder" { return title.hasSuffix(" Info") }
        if let regex = Self.signInTitle,
           regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil { return true }
        let name = NSRunningApplication(processIdentifier: window.pid)?.localizedName
        let settings = ["Settings", "Preferences", "Settings…", "Preferences…"]
        return settings.contains(title) || name.map { app in settings.contains { title == "\(app) \($0)" } } == true
    }

    private func isMountedImageWindow(title: String?) -> Bool {
        guard let title, !title.isEmpty else { return false }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                            options: [.skipHiddenVolumes]) ?? []
        return volumes.contains { url in
            guard url.path != "/", let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.volumeName == title && (values.volumeIsEjectable == true || values.volumeIsInternal == false)
        }
    }

    package func shouldFloat(_ window: Window) -> Bool {
        shouldFloat(window, title: window.title, resizable: window.resizable)
    }

    package func shouldFloat(_ window: Window, title: String?, resizable: Bool) -> Bool {
        if let practice, window.pid == practice.pid { return false }
        if let bundle = window.bundleID,
           bundle == Bundle.main.bundleIdentifier || bundle.hasPrefix("local.catwm")
            || Legacy.isBundle(bundle) {
            return true
        }
        if let bundle = window.bundleID, Self.alwaysFloatingApps.contains(bundle) { return true }
        if window.bundleID == "com.apple.finder", isMountedImageWindow(title: title) { return true }
        if isUtilityWindow(window, title: title) { return true }
        if let bundle = window.bundleID {
            let listed = Config.lists(bundle, in: config.floating)
            if config.floatingIsDenylist ? listed : !listed { return true }
        } else if !config.floatingIsDenylist {
            return true
        }
        if !resizable { return true }
        let frame = window.naturalFrame
        if config.floatSmallWindows, !frame.isNull, frame.width < 500, frame.height < 500 { return true }
        return false
    }
}

package func axCallback(_: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _: UnsafeMutableRawPointer?) {
    WindowManager.shared.handle(notification as String, element)
}

extension WindowManager {
    package static let restoreHold: TimeInterval = 1.5

    package func claimForCurrentWorkspace(_ ids: [CGWindowID]) {
        guard config.virtualWorkspaces, !restoringTemplate, let here = currentWorkspace else { return }
        for id in ids where workspaceOf[id] != here {
            guard let target = desktops.nativeCatalog.entry(here),
                  Spaces.of(window: id).contains(target.space) else { continue }
            model.assign(id, to: here)
        }
    }

    package func windowMinimizeChanged(_ element: AXUIElement, minimized: Bool) {
        guard let window = windows.values.first(where: { CFEqual($0.element, element) }),
              window.minimized != minimized else {
            return scheduleRefresh(after: 0)
        }
        window.minimized = minimized
        window.observedAt = Date()
        guard !minimized else { return scheduleRefresh(after: 0) }
        claimForCurrentWorkspace([window.id])
        restoreTabGroup(of: window.id)
        restoredEarly[window.id] = Date()
        snapNextPlacement.insert(window.id)
        refresh(instant: true, placing: [window.id])
        scheduleRefresh(after: 0)
    }

    package func prewarm() {
        guard !isStarted else { return }
        scanner.observeDesktop(known: []) {}
    }
}
