import AppKit

extension WindowManager {
    private struct ObservedWindows {
        package var present = Set<CGWindowID>()
        package var fresh: [Window] = []
        package var titles: [CGWindowID: String?] = [:]
    }

    private struct PlannedMoves {
        package var moves: [Animator.Move] = []
        package var instant: [Animator.Move] = []
        package var motion: [(moves: [Animator.Move], spec: MotionSpec)] = []
    }

    package func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        guard isStarted, !nativeDesktop.isRunning, !desktops.nativeCreationBusy else { return }
        let timing = TilingTiming("refresh", windows: windows.count)
        defer { timing.finish(); applyDueWindowRules() }
        if scanner.lastScan == 0 { scheduleRefresh(after: 0) }
        let screens = backend.screens()
        timing.checkpoint("screens")
        guard !screens.isEmpty else { return }
        if config.virtualWorkspaces {
            if DesktopUI.isBusy(on: screens) { scheduleRefresh(after: 0.15); return }
            timing.checkpoint("desktop UI")
            updateNativeCatalog(screens)
            timing.checkpoint("catalog")
        }

        let onScreen = scanner.desktop.windows
        let onScreenIDs = Set(onScreen.map(\.id))
        let firstRun = windows.isEmpty
        updateKnownWindows()
        timing.checkpoint("known windows")
        var observed = observeWindows(screens: screens, onScreen: onScreen)
        timing.checkpoint("observe")
        observed.present.formUnion(nativeMoves.movingIDs.filter { windows[$0] != nil })
        restoredEarly = restoredEarly.filter { id, since in
            windows[id]?.minimized == false && !onScreenIDs.contains(id)
                && Date().timeIntervalSince(since) < Self.restoreHold
        }
        observed.present.formUnion(restoredEarly.keys)

        let arrivals = placeArrivals(observed, onScreen: onScreen)
        forgetGoneWindows(present: observed.present)
        self.present = observed.present
        let plan = syncWorkspaces(screens: screens, present: observed.present)
        visible = plan.visible
        resolveWorkspaces(screens: screens, arrivals: arrivals, firstRun: firstRun, timing: timing)
        guard !restoringTemplate else { notifyChange(); return }
        restoreTilingRecovery(observed.fresh)
        saveWorkspaces()

        timing.checkpoint("workspaces")
        surface.refreshed(screens)
        refocusAfterCloseIfNeeded(hasFresh: !observed.fresh.isEmpty)

        restoreTabs()
        settleTabs()
        saveTilingRecovery()
        guard tilingEnabled else {
            surface.tilesDidChange(instant: false); notifyChange(); return
        }
        applyTileMoves(planTileMoves(screens: screens, only: only), instant: instantLayout)
        surface.tilesDidChange(instant: instantLayout || dividerState.dividerDrag != nil)
        timing.checkpoint("apply")
        notifyChange()
        timing.checkpoint("notify")
    }

    private func refocusAfterCloseIfNeeded(hasFresh: Bool) {
        guard let workspace = focusRequests.takeRefocusAfterClose() else { return }
        guard !hasFresh else { return }
        DispatchQueue.main.asyncAfter( // style-ok: grace time for the app to pick its own next window
            deadline: .now() + 0.1
        ) { [weak self] in
            self?.refocusRecent(on: workspace)
        }
    }

    private func applyTileMoves(_ planned: PlannedMoves, instant instantLayout: Bool) {
        if !planned.moves.isEmpty {
            Log.debug("tile: moving \(planned.moves.map { "\($0.window.id)→\($0.target)" }.joined(separator: ", "))")
        }
        if dividerState.dividerDrag != nil {
            animator.follow(planned.instant + planned.moves)
            return
        }
        animator.animate(planned.instant, duration: 0)
        animator.animate(planned.motion.map { batch in
            let animated = !instantLayout && batch.spec.duration > 0 && batch.moves.count <= Self.maxAnimatedMoves
            return Animator.Batch(moves: batch.moves, spec: animated ? batch.spec : .instant)
        })
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
        unminimized.forEach(restoreTabGroup)
    }

    private func observeWindows(screens: [Screen], onScreen: [CGWindowInfo]) -> ObservedWindows {
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let currentSpaces = Set(screens.map { backend.currentSpace(display: $0.uuid) })
        func onOtherSpace(_ id: CGWindowID) -> Bool {
            let spaces = scanner.desktop.spaces[id] ?? []
            return !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        }
        let nativeSpaces = Set(desktops.nativeCatalog.entries.map(\.space))
        func managed(_ id: CGWindowID) -> Bool {
            config.virtualWorkspaces && !(scanner.desktop.spaces[id] ?? []).isDisjoint(with: nativeSpaces)
        }
        var observed = ObservedWindows()
        for app in observedApps {
            let pid = app.pid
            guard let scan = scanner.results[pid], pidsOnScreen.contains(pid) || config.virtualWorkspaces else {
                continue
            }
            let listed = Set(scan.listed)
            for id in scan.listed + scan.found.keys.filter({ !listed.contains($0) }) {
                let maximised = scan.fullscreen.contains(id)
                guard !nativeMoves.isMoving(id),
                      maximised || managed(id) || (onScreenIDs.contains(id) && !onOtherSpace(id)) else {
                    continue
                }
                if let window = windows[id] {
                    if observeKnown(window, id: id, scan: scan), onScreenIDs.contains(id) {
                        observed.present.insert(id)
                    }
                    continue
                }
                guard let found = scan.found[id], !found.frame.isNull else { continue }
                let window = Window(id: id, element: found.element, pid: pid, bundleID: app.bundleID, backend: backend)
                accept(found, from: scan, for: window)
                if !maximised { window.naturalFrame = found.frame }
                window.autoFloating = shouldFloat(window, title: found.title, resizable: found.resizable || maximised)
                observed.titles[id] = found.title
                windows[id] = window
                markForRules(window)
                watch(window)
                observed.fresh.append(window)
                if onScreenIDs.contains(id), !maximised { observed.present.insert(id) }
            }
        }
        return observed
    }

    private func observeKnown(_ window: Window, id: CGWindowID, scan: WindowScanner.AppScan) -> Bool {
        if let found = scan.found[id] { accept(found, from: scan, for: window) }
        let wasHeld = window.placementSuspended
        guard placementHolds.observe(window, scanStarted: scan.readAt, minimized: scan.minimized.contains(id),
                                     fullscreen: scan.fullscreen.contains(id), restoring: restoringTemplate) else {
            return false
        }
        if wasHeld && !window.placementSuspended { snapNextPlacement.insert(id) }
        return !(scan.fullscreen.contains(id) || scan.minimized.contains(id))
    }

    private func placeArrivals(_ observed: ObservedWindows, onScreen: [CGWindowInfo]) -> [Window] {
        let fresh = observed.fresh
        let stacking = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let arrivals = fresh.sorted(by: { (stacking[$0.id] ?? 0) < (stacking[$1.id] ?? 0) })
        for window in arrivals where config.virtualWorkspaces {
            restoreSavedWorkspace(window, titles: observed.titles)
        }
        if !pendingLaunches.isEmpty { arrivals.forEach(claimLaunch) }
        for window in fresh {
            Log.debug(
                "new window \(window.id) \(window.bundleID ?? "pid \(window.pid)") "
                    + "floating=\(window.isFloating) frame=\(window.cachedFrame)"
            )
        }
        if !fresh.isEmpty { scheduleRefresh(after: 0.4) }
        return arrivals
    }

    private func resolveWorkspaces(screens: [Screen], arrivals: [Window], firstRun: Bool, timing: TilingTiming) {
        resolveWorkspaceConfigs(screens: screens)
        timing.checkpoint("workspace rules")
        guard !arrivals.isEmpty else { return }
        let toMain = firstRun ? [] : arrivals.filter { config(for: workspaceOf[$0.id]).newWindowsToMain }
        order.insert(contentsOf: toMain.map(\.id), at: 0)
        let ids = Set(toMain.map(\.id))
        let rest = arrivals.map(\.id).filter { !ids.contains($0) }
        let focusedID = [focusRequests.reportedFocus?.id, focusedWindow()?.id].compactMap(\.self)
            .first { order.contains($0) }
        if !firstRun, let focused = focusedID.flatMap({ windows[$0] }), let at = order.firstIndex(of: focused.id),
           let screen = screen(of: focused), state(for: screen).layout == .dwindle {
            order.insert(contentsOf: rest, at: at + 1)
        } else {
            order.append(contentsOf: rest)
        }
    }

    private func restoreSavedWorkspace(_ window: Window, titles: [CGWindowID: String?]) {
        if floats.savedOwnerOf[window.id] == owner(window) {
            if let float = floats.savedFloating[window.id] { window.userFloating = .chosen(float) }
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
            let appGone = !backend.isRunning(window.pid)
            if appGone || scanner.results[window.pid]?.gone.contains(id) == true {
                forget(id, keepRecovery: appGone || isPoweringOff)
            }
        }
    }

    private func planTileMoves(screens: [Screen], only: Set<CGWindowID>?) -> PlannedMoves {
        var planned = PlannedMoves()
        for screen in screens {
            let firstMove = planned.moves.count
            defer {
                if planned.moves.count > firstMove {
                    planned.motion.append((Array(planned.moves[firstMove...]), motion(on: screen)))
                }
            }
            let screenState = state(for: screen)
            let ids = tiled(on: screen).filter { !nativeMoves.isMoving($0) }
            if let zoomed = screenState.zoomed,
               windows[zoomed]?.isFloating != false || workspaceOf[zoomed] != shown[screen.uuid] {
                screenState.zoomed = nil
            }
            guard let slots = layoutTargets(ids, screenState, on: screen) else {
                ids.forEach { targets[$0] = nil }
                continue
            }
            for id in ids {
                guard let slot = slots[id] else { continue }
                let target = belowTabStrip(slot, for: id)
                for member in [id] + tabStack(behind: id) {
                    targets[member] = target
                    if let only, !only.contains(member) { continue }
                    if member == tabUI.drag.lifted || member != id && drags[id] != nil { continue }
                    guard let window = windows[member], member == id || !covered(window, by: target) else { continue }
                    planMove(window, to: target, on: screen, screens: screens, into: &planned)
                }
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

    package func accept(_ found: WindowScanner.Found, from scan: WindowScanner.AppScan, for window: Window) {
        guard scan.readAt > window.observedAt else { return }
        let wasResizable = window.resizable || window.fullscreen
        window.observedAt = scan.readAt
        window.minimized = scan.minimized.contains(window.id)
        window.fullscreen = scan.fullscreen.contains(window.id)
        window.remember(found.frame, ifRevision: found.frameRevision ?? window.frameRevision, readAt: scan.readAt)
        let retitled = window.title != found.title
        window.title = found.title
        window.resizable = found.resizable
        let resizable = window.resizable || window.fullscreen
        if retitled, !tabs.isGrouped(window.id), windows[window.id] === window { markForRules(window) }
        if (retitled && !tabs.isGrouped(window.id)) || wasResizable != resizable {
            window.autoFloating = shouldFloat(window, title: window.title, resizable: resizable)
            corrections[window.id] = nil
        }
        if retitled { surface.titleChanged(window) }
    }

    package func refocusRecent(on workspace: String) {
        guard isShown(workspace), focusRequests.pendingFocus == nil else { return }
        guard let pid = frontmostPID() else { return }
        guard let report = focusRequests.reportedFocus, report.pid == pid else {
            focusRequests.waitToRefocus(on: workspace, pid: pid)
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

    package func layoutTargets(_ ids: [CGWindowID], _ screenState: ScreenState, on screen: Screen,
                               workspace: String? = nil) -> [CGWindowID: CGRect]? {
        guard let (raw, gap) = rawSlots(ids, on: screen, screenState, ratio: screenState.ratio,
                                        workspace: workspace) else { return nil }
        let slots = fitMinimums(raw, mins: ids.map(slotMinimum), gap: gap)
        let zoomed = usableRect(screen, workspace: workspace).pixelAligned
        let bounds = screen.visible
        return Dictionary(zip(ids, slots).map { id, slot in
            (id, id == screenState.zoomed ? zoomed : clampToMinimum(slot, min: slotMinimum(id), bounds: bounds))
        },
                          uniquingKeysWith: { first, _ in first })
    }
}
