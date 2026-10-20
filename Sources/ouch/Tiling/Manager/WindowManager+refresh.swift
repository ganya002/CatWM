import AppKit

extension WindowManager {
    private struct ObservedWindows {
        var present = Set<CGWindowID>()
        var fresh: [Window] = []
        var titles: [CGWindowID: String?] = [:]
    }

    private struct PlannedMoves {
        var moves: [Animator.Move] = []
        var instant: [Animator.Move] = []
    }

    func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        guard isStarted, !nativeDesktop.isRunning, !nativeCreationBusy else { return }
        let timing = TilingTiming("refresh", windows: windows.count)
        defer { timing.finish() }
        if scanner.lastScan == 0 { scheduleRefresh(after: 0) }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        if config.virtualWorkspaces {
            if screens.contains(where: DesktopUI.isBusy) { scheduleRefresh(after: 0.15); return }
            updateNativeCatalog(screens)
        }

        let onScreen = scanner.desktop.windows
        let onScreenIDs = Set(onScreen.map(\.id))
        let firstRun = windows.isEmpty
        updateKnownWindows()
        var observed = observeWindows(screens: screens, onScreen: onScreen)
        timing.checkpoint("observe")
        observed.present.formUnion(workspaceMoves.filter { windows[$0] != nil })
        restoredEarly = restoredEarly.filter { id, since in
            windows[id]?.minimized == false && !onScreenIDs.contains(id)
                && Date().timeIntervalSince(since) < Self.restoreHold
        }
        observed.present.formUnion(restoredEarly.keys)

        placeArrivals(observed, onScreen: onScreen, firstRun: firstRun)
        forgetGoneWindows(present: observed.present)
        self.present = observed.present
        let plan = syncWorkspaces(screens: screens, present: observed.present)
        visible = plan.visible
        guard !restoringTemplate else { onChange?(); return }
        if config.virtualWorkspaces {
            saveWorkspaces()
        }

        timing.checkpoint("workspaces")
        watchCrowding(screens)
        refocusAfterCloseIfNeeded(hasFresh: !observed.fresh.isEmpty)

        guard tilingEnabled else { onChange?(); return }
        applyTileMoves(planTileMoves(screens: screens, only: only), instant: instantLayout)
        timing.checkpoint("apply")
        onChange?()
        timing.checkpoint("notify")
    }

    private func refocusAfterCloseIfNeeded(hasFresh: Bool) {
        guard let workspace = refocusAfterClose else { return }
        refocusAfterClose = nil
        guard !hasFresh else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.refocusRecent(on: workspace)
        }
    }

    private func applyTileMoves(_ planned: PlannedMoves, instant instantLayout: Bool) {
        if !planned.moves.isEmpty {
            Log.debug("tile: moving \(planned.moves.map { "\($0.window.id)→\($0.target)" }.joined(separator: ", "))")
        }
        animator.animate(planned.instant, duration: 0)
        let animated = !instantLayout && config.animate && planned.moves.count <= Self.maxAnimatedMoves
        animator.animate(planned.moves, duration: animated ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
    }

    private func updateKnownWindows() {
        var unminimized: [CGWindowID] = []
        for scan in scanner.results.values {
            for (id, found) in scan.found {
                guard let window = windows[id] else { continue }
                let wasMinimized = window.minimized
                accept(found, from: scan, for: window)
                if wasMinimized && !window.minimized { unminimized.append(id) }
            }
        }
        claimForCurrentWorkspace(unminimized)
    }

    private func observeWindows(screens: [Screen], onScreen: [CGWindowInfo]) -> ObservedWindows {
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let currentSpaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        func onOtherSpace(_ id: CGWindowID) -> Bool {
            let spaces = scanner.desktop.spaces[id] ?? []
            return !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        }
        let nativeSpaces = Set(nativeCatalog.entries.map(\.space))
        func managed(_ id: CGWindowID) -> Bool {
            config.virtualWorkspaces && !(scanner.desktop.spaces[id] ?? []).isDisjoint(with: nativeSpaces)
        }
        var observed = ObservedWindows()
        for app in observedApps {
            let pid = app.pid
            guard let scan = scanner.results[pid], pidsOnScreen.contains(pid) || config.virtualWorkspaces else {
                continue
            }
            for id in scan.listed {
                guard !workspaceMoves.contains(id),
                      managed(id) || (onScreenIDs.contains(id) && !onOtherSpace(id)) else {
                    continue
                }
                if let window = windows[id] {
                    if observeKnown(window, id: id, scan: scan), onScreenIDs.contains(id) {
                        observed.present.insert(id)
                    }
                    continue
                }
                guard let found = scan.found[id], !found.frame.isNull else { continue }
                let window = Window(id: id, element: found.element, pid: pid, bundleID: app.bundleID)
                accept(found, from: scan, for: window)
                window.naturalFrame = found.frame
                window.autoFloating = shouldFloat(window, title: found.title, resizable: found.resizable)
                observed.titles[id] = found.title
                windows[id] = window
                watch(window)
                observed.fresh.append(window)
                if onScreenIDs.contains(id) { observed.present.insert(id) }
            }
        }
        return observed
    }

    private func observeKnown(_ window: Window, id: CGWindowID, scan: WindowScanner.AppScan) -> Bool {
        if let found = scan.found[id] { accept(found, from: scan, for: window) }
        if let since = templateHiddenWindows[id] {
            let release = TemplatePlacementPlan.releaseHeldWindow(
                scanStarted: scan.readAt, heldSince: since, minimized: scan.minimized.contains(id),
                fullscreen: scan.fullscreen.contains(id), restoring: restoringTemplate)
            guard release else { return false }
            templateHiddenWindows[id] = nil
            windows[id]?.placementSuspended = false
            snapNextPlacement.insert(id)
        }
        return !(scan.fullscreen.contains(id) || scan.minimized.contains(id))
    }

    private func placeArrivals(_ observed: ObservedWindows, onScreen: [CGWindowInfo], firstRun: Bool) {
        let fresh = observed.fresh
        let stacking = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arrivals = fresh.sorted(by: { (stacking[$0.id] ?? 0) < (stacking[$1.id] ?? 0) })
        for window in arrivals where config.virtualWorkspaces {
            restoreSavedWorkspace(window, titles: observed.titles)
        }
        if config.newWindowsToMain && !firstRun {
            order.insert(contentsOf: arrivals.map(\.id), at: 0)
        } else {
            order.append(contentsOf: arrivals.map(\.id))
        }
        for window in fresh {
            Log.debug(
                "new window \(window.id) \(window.bundleID ?? "pid \(window.pid)") "
                    + "floating=\(window.isFloating) frame=\(window.cachedFrame)"
            )
        }
        if !fresh.isEmpty { scheduleRefresh(after: 0.4) }
    }

    private func restoreSavedWorkspace(_ window: Window, titles: [CGWindowID: String?]) {
        if savedOwnerOf[window.id] == owner(window) {
            if let float = savedFloating[window.id] { window.userFloating = .chosen(float) }
        }
        restoreNativeMigration(window)
        if let practice, window.pid == practice.pid,
           let workspace = titles[window.id].flatMap(\.self).flatMap({ practice.workspaces[$0] }) {
            model.assign(window.id, to: workspace)
            if monitorOf[workspace] == nil, let here = currentScreen() { monitorOf[workspace] = here.uuid }
        }
    }

    private func forgetGoneWindows(present: Set<CGWindowID>) {
        for (id, window) in windows where !present.contains(id) {
            if NSRunningApplication(processIdentifier: window.pid) == nil
                || scanner.results[window.pid]?.gone.contains(id) == true {
                forget(id)
            }
        }
    }

    private func planTileMoves(screens: [Screen], only: Set<CGWindowID>?) -> PlannedMoves {
        var planned = PlannedMoves()
        for screen in screens {
            let screenState = state(for: screen)
            let ids = tiled(on: screen).filter { !workspaceMoves.contains($0) }
            if let zoomed = screenState.zoomed,
               windows[zoomed]?.isFloating != false || workspaceOf[zoomed] != shown[screen.uuid] {
                screenState.zoomed = nil
            }
            guard let slots = layoutTargets(ids, screenState, on: screen) else {
                ids.forEach { targets[$0] = nil }
                continue
            }
            for id in ids {
                guard let target = slots[id] else { continue }
                targets[id] = target
                if let only, !only.contains(id) { continue }
                guard let window = windows[id] else { continue }
                planMove(window, to: target, on: screen, screens: screens, into: &planned)
            }
        }
        return planned
    }

    private func planMove(
        _ window: Window, to target: CGRect, on screen: Screen, screens: [Screen], into planned: inout PlannedMoves
    ) {
        let id = window.id
        let snap = snapNextPlacement.remove(id) != nil
        let current = animator.destination(id) ?? window.cachedFrame
        if current.isNull || current.approxEqual(target) {
            corrections[id] = nil
            return
        }
        if snap {
            planned.instant.append(.init(window: window, to: target, bounds: screen.visible))
            return
        }
        if isParked(current, screens) {
            if let from = slideStart(id, to: target, on: screen) {
                planned.moves.append(.init(window: window, to: target, bounds: screen.visible, from: from))
            } else {
                planned.instant.append(.init(window: window, to: target, bounds: screen.visible))
            }
            return
        }
        if animator.isMoving(id, to: target) { return }
        if animator.isBusy(id) {
            planned.moves.append(.init(window: window, to: target, bounds: screen.visible))
            return
        }
        var correction = corrections[id] ?? (target, 0)
        if correction.target != target { correction = (target, 0) }
        correction.count += 1
        corrections[id] = correction
        if correction.count > 3 { return }
        planned.moves.append(.init(window: window, to: target, bounds: screen.visible))
    }

    func accept(_ found: WindowScanner.Found, from scan: WindowScanner.AppScan, for window: Window) {
        guard scan.readAt > window.observedAt else { return }
        window.observedAt = scan.readAt
        window.minimized = scan.minimized.contains(window.id)
        window.fullscreen = scan.fullscreen.contains(window.id)
        window.remember(found.frame, ifRevision: found.frameRevision ?? window.frameRevision, readAt: scan.readAt)
        window.title = found.title
        window.resizable = found.resizable
    }

    func refocusRecent(on workspace: String) {
        guard isShown(workspace), pendingFocus == nil else { return }
        guard let pid = frontmostPID() else { return }
        guard let report = reportedFocus, report.pid == pid else {
            waitingRefocus = (workspace, pid)
            requestFocusObservation()
            return
        }
        if let id = report.id, windows[id] == nil { return }
        let here = visible.filter { workspaceOf[$0] == workspace }
        guard let id = model.mostRecent(of: here), reportedFocusedWindow()?.id != id,
              let window = windows[id] else { return }
        Log.debug("focus: window closed; back to \(id)")
        focus(window)
    }

    func layoutTargets(_ ids: [CGWindowID], _ screenState: ScreenState, on screen: Screen) -> [CGWindowID: CGRect]? {
        guard let (raw, gap) = rawSlots(ids, on: screen, screenState, ratio: screenState.ratio) else { return nil }
        let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
        let zoomed = usableRect(screen).pixelAligned
        return Dictionary(zip(ids, slots).map { id, slot in (id, id == screenState.zoomed ? zoomed : slot) },
                          uniquingKeysWith: { first, _ in first })
    }
}
