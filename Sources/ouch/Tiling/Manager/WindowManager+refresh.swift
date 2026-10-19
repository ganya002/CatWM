import AppKit

extension WindowManager {
    func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        guard isStarted else { return }
        let timing = TilingTiming("refresh", windows: windows.count)
        defer { timing.finish() }
        if scanner.lastScan == 0 { scheduleRefresh(after: 0) }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }

        let onScreen = scanner.desktop.windows
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let firstRun = windows.isEmpty
        let currentSpaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        func onOtherSpace(_ id: CGWindowID) -> Bool {
            let spaces = scanner.desktop.spaces[id] ?? []
            return !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        }
        var unminimized: [CGWindowID] = []
        for scan in scanner.results.values {
            for (id, found) in scan.found {
                guard let w = windows[id] else { continue }
                let wasMinimized = w.minimized
                accept(found, from: scan, for: w)
                if wasMinimized && !w.minimized { unminimized.append(id) }
            }
        }
        if config.virtualWorkspaces, !restoringTemplate, !unminimized.isEmpty, let here = currentWorkspace {
            for id in unminimized where workspaceOf[id] != here { model.assign(id, to: here) }
        }
        var present = Set<CGWindowID>()
        var fresh: [Window] = []
        var titles: [CGWindowID: String?] = [:]

        for app in observedApps {
            let pid = app.pid
            guard pidsOnScreen.contains(pid), let scan = scanner.results[pid] else { continue }
            for id in scan.listed {
                guard !workspaceMoves.contains(id), onScreenIDs.contains(id), !onOtherSpace(id) else { continue }
                if let w = windows[id] {
                    if let found = scan.found[id] { accept(found, from: scan, for: w) }
                    if let since = templateHiddenWindows[id] {
                        let release = TemplatePlacementPlan.releaseHeldWindow(
                            scanStarted: scan.readAt, heldSince: since, minimized: scan.minimized.contains(id),
                            fullscreen: scan.fullscreen.contains(id), restoring: restoringTemplate)
                        guard release else { continue }
                        templateHiddenWindows[id] = nil
                        windows[id]?.placementSuspended = false
                        snapNextPlacement.insert(id)
                    }
                    if scan.fullscreen.contains(id) || scan.minimized.contains(id) { continue }
                    present.insert(id)
                    continue
                }
                guard let found = scan.found[id], !found.frame.isNull else { continue }
                let w = Window(id: id, element: found.element, pid: pid, bundleID: app.bundleID)
                accept(found, from: scan, for: w)
                w.naturalFrame = found.frame
                w.autoFloating = shouldFloat(w, title: found.title, resizable: found.resizable)
                titles[id] = found.title
                windows[id] = w
                watch(w)
                fresh.append(w)
                present.insert(id)
            }
        }
        timing.checkpoint("observe")
        present.formUnion(workspaceMoves.filter { windows[$0] != nil })

        let z = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let arrivals = fresh.sorted(by: { (z[$0.id] ?? 0) < (z[$1.id] ?? 0) })
        for w in arrivals where config.virtualWorkspaces {
            if savedOwnerOf[w.id] == owner(w) {
                if let saved = savedWorkspaceOf[w.id] { model.assign(w.id, to: saved) }
                if let float = savedFloating[w.id] { w.userFloating = float }
            }
            if let p = practice, w.pid == p.pid, let ws = titles[w.id].flatMap({ $0 }).flatMap({ p.workspaces[$0] }) {
                model.assign(w.id, to: ws)
                if monitorOf[ws] == nil, let here = currentScreen() { monitorOf[ws] = here.uuid }
            }
        }
        if config.newWindowsToMain && !firstRun { order.insert(contentsOf: arrivals.map(\.id), at: 0) } else { order.append(contentsOf: arrivals.map(\.id)) }
        for w in fresh {
            Log.debug("new window \(w.id) \(w.bundleID ?? "pid \(w.pid)") floating=\(w.isFloating) frame=\(w.cachedFrame)")
        }
        if !fresh.isEmpty { scheduleRefresh(after: 0.4) }

        for (id, w) in windows where !present.contains(id) {
            if NSRunningApplication(processIdentifier: w.pid) == nil || scanner.results[w.pid]?.gone.contains(id) == true { forget(id) }
        }
        self.present = present
        let plan = syncWorkspaces(screens: screens, present: present)
        visible = plan.visible
        guard !restoringTemplate else { onChange?(); return }
        if config.virtualWorkspaces {
            for id in plan.park { park(id, screens: screens) }
            for id in visible where floatsFreely(id) { unpark(floating: id, screens: screens) }
            saveWorkspaces()
        }

        timing.checkpoint("workspaces")
        watchCrowding(screens)
        if let ws = refocusAfterClose {
            refocusAfterClose = nil
            if fresh.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.refocusRecent(on: ws) } }
        }

        guard tilingEnabled else { onChange?(); return }
        var moves: [Animator.Move] = [], instant: [Animator.Move] = []
        for s in screens {
            let st = state(for: s)
            let ids = tiled(on: s)
            if let z = st.zoomed, windows[z]?.isFloating != false || workspaceOf[z] != shown[s.uuid] { st.zoomed = nil }
            guard let slots = layoutTargets(ids, st, on: s) else {
                ids.forEach { targets[$0] = nil }
                continue
            }
            for id in ids {
                guard let target = slots[id] else { continue }
                targets[id] = target
                if let only, !only.contains(id) { continue }
                guard let w = windows[id] else { continue }
                let snap = snapNextPlacement.remove(id) != nil
                let current = animator.destination(id) ?? w.cachedFrame
                if current.isNull || current.approxEqual(target) { corrections[id] = nil; continue }
                if snap {
                    instant.append(.init(window: w, to: target, bounds: s.visible))
                    continue
                }
                if isParked(current, screens) {
                    if let from = slideStart(id, to: target, on: s) {
                        moves.append(.init(window: w, to: target, bounds: s.visible, from: from))
                    } else {
                        instant.append(.init(window: w, to: target, bounds: s.visible))
                    }
                    continue
                }
                if animator.isMoving(id, to: target) { continue }
                if animator.isBusy(id) { moves.append(.init(window: w, to: target, bounds: s.visible)); continue }
                var c = corrections[id] ?? (target, 0)
                if c.target != target { c = (target, 0) }
                c.count += 1
                corrections[id] = c
                if c.count > 3 { continue }
                moves.append(.init(window: w, to: target, bounds: s.visible))
            }
        }
        if !moves.isEmpty { Log.debug("tile: moving \(moves.map { "\($0.window.id)→\($0.to)" }.joined(separator: ", "))") }
        animator.animate(instant, duration: 0)
        let animated = !instantLayout && config.animate && moves.count <= Self.maxAnimatedMoves
        animator.animate(moves, duration: animated ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
        timing.checkpoint("apply")
        onChange?()
        timing.checkpoint("notify")
    }

    func accept(_ found: WindowScanner.Found, from scan: WindowScanner.AppScan, for w: Window) {
        guard scan.readAt > w.observedAt else { return }
        w.observedAt = scan.readAt
        w.minimized = scan.minimized.contains(w.id)
        w.fullscreen = scan.fullscreen.contains(w.id)
        w.remember(found.frame, ifRevision: found.frameRevision ?? w.frameRevision, readAt: scan.readAt)
        w.title = found.title
        w.resizable = found.resizable
    }

    func refocusRecent(on ws: String) {
        guard isShown(ws), pendingFocus == nil else { return }
        guard let pid = frontmostPID() else { return }
        guard let report = reportedFocus, report.pid == pid else {
            waitingRefocus = (ws, pid)
            requestFocusObservation()
            return
        }
        if let id = report.id, windows[id] == nil { return }
        let here = visible.filter { workspaceOf[$0] == ws }
        guard let id = model.mostRecent(of: here), reportedFocusedWindow()?.id != id, let w = windows[id] else { return }
        Log.debug("focus: window closed; back to \(id)")
        focus(w)
    }

    func layoutTargets(_ ids: [CGWindowID], _ st: ScreenState, on s: Screen) -> [CGWindowID: CGRect]? {
        guard let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else { return nil }
        let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
        let zoomed = usableRect(s).pixelAligned
        return Dictionary(zip(ids, slots).map { id, slot in (id, id == st.zoomed ? zoomed : slot) }, uniquingKeysWith: { a, _ in a })
    }

}
