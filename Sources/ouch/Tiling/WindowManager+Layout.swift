import AppKit

extension WindowManager {

    static let maxAnimatedMoves = 6

    func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAndRefresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    private func scanAndRefresh() {
        refreshWork = nil
        guard isStarted else { return }
        let pidsOnScreen = Set(CGWindowInfo.onScreen().map(\.pid))
        var known: [pid_t: [CGWindowID: Window]] = [:]
        for w in windows.values { known[w.pid, default: [:]][w.id] = w }
        var jobs: [WindowScanner.Job] = []
        for app in NSWorkspace.shared.runningApplications where app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            let list = app.activationPolicy == .regular && !app.isHidden && pidsOnScreen.contains(pid)
            guard list || known[pid] != nil else { continue }
            jobs.append(.init(pid: pid, listWindows: list, known: known[pid] ?? [:]))
        }
        scanner.scan(jobs, done: { [weak self] in self?.refresh() }, late: { [weak self] in self?.refresh() })
    }

    func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        guard isStarted else { return }
        if scanner.lastScan == 0 { scheduleRefresh(after: 0) }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }

        let onScreen = CGWindowInfo.onScreen()
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let firstRun = windows.isEmpty
        let currentSpaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        func onOtherSpace(_ id: CGWindowID) -> Bool {
            let spaces = Spaces.of(window: id)
            return !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        }
        var present = Set<CGWindowID>()
        var fresh: [Window] = []
        var titles: [CGWindowID: String?] = [:]

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            observe(app)
            let pid = app.processIdentifier
            guard pidsOnScreen.contains(pid), let scan = scanner.results[pid] else { continue }
            for id in scan.listed {
                guard !workspaceMoves.contains(id), onScreenIDs.contains(id), !onOtherSpace(id) else { continue }
                if windows[id] != nil {
                    if !scan.fullscreen.contains(id) { present.insert(id) }
                    continue
                }
                guard let found = scan.found[id] else { continue }
                let w = Window(id: id, element: found.element, pid: pid, bundleID: app.bundleIdentifier)
                w.remember(found.frame)
                w.naturalFrame = found.frame
                w.autoFloating = shouldFloat(w, title: found.title, resizable: found.resizable)
                titles[id] = found.title
                windows[id] = w
                watch(w)
                fresh.append(w)
                present.insert(id)
            }
        }
        present.formUnion(workspaceMoves.filter { windows[$0] != nil })

        let z = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let arrivals = fresh.sorted(by: { (z[$0.id] ?? 0) < (z[$1.id] ?? 0) })
        for w in arrivals where config.virtualWorkspaces {
            if savedOwnerOf[w.id] == owner(w) {
                if let saved = savedWorkspaceOf[w.id] { workspaceOf[w.id] = saved }
                if let float = savedFloating[w.id] { w.userFloating = float }
            }
            if let p = practice, w.pid == p.pid, let ws = titles[w.id].flatMap({ $0 }).flatMap({ p.workspaces[$0] }) {
                workspaceOf[w.id] = ws
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
        syncWorkspaces(screens: screens, present: present)
        visible = present.filter { isShown(workspaceOf[$0]) }
        if config.virtualWorkspaces {
            for id in present where !visible.contains(id) { park(id, screens: screens) }
            for id in visible where floatsFreely(id) { unpark(floating: id, screens: screens) }
            saveWorkspaces()
        }

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
            let rect = usableRect(s)
            guard let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else {
                ids.forEach { targets[$0] = nil }
                continue
            }
            let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
            for (id, slot) in zip(ids, slots) {
                let target = id == st.zoomed ? rect.pixelAligned : slot
                targets[id] = target
                if let only, !only.contains(id) { continue }
                guard let w = windows[id] else { continue }
                let snap = snapNextPlacement.remove(id) != nil
                let current = w.cachedFrame
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
        onChange?()
    }

    private func refocusRecent(on ws: String) {
        guard isShown(ws), pendingFocus == nil else { return }
        if let app = NSWorkspace.shared.frontmostApplication,
           let id = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID,
           windows[id] == nil { return }
        let here = visible.filter { workspaceOf[$0] == ws }
        guard let id = here.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }), focusStamps[id] != nil,
              reportedFocusedWindow()?.id != id, let w = windows[id] else { return }
        Log.debug("focus: window closed; back to \(id)")
        focus(w)
    }

    func rawSlots(_ ids: [CGWindowID], on s: Screen, _ st: ScreenState, ratio: CGFloat) -> ([CGRect], CGFloat)? {
        let gap = config.windowMargins && !(config.smartWindowMargins && ids.count == 1) ? config.windowMarginSize : 0
        guard let raw = st.layout.frames(count: ids.count, in: usableRect(s).insetBy(dx: -gap / 2, dy: -gap / 2),
                                         ratio: ratio, mainCount: st.mainCount) else { return nil }
        let slots = raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned }
        guard slots.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        return (slots, gap)
    }

    func windowRefusingRatio(_ ratio: CGFloat, from old: CGFloat, ids: [CGWindowID], on s: Screen, _ st: ScreenState) -> CGWindowID? {
        guard ids.contains(where: { minSizes[$0] != nil }),
              let (before, _) = rawSlots(ids, on: s, st, ratio: old),
              let (after, _) = rawSlots(ids, on: s, st, ratio: ratio) else { return nil }
        return zip(ids, zip(before, after)).first { id, slots in
            guard let m = minSizes[id] else { return false }
            let (b, a) = slots
            return (m.width > a.width + 1 && a.width < b.width - 1) || (m.height > a.height + 1 && a.height < b.height - 1)
        }?.0
    }

    func warnTooSmall(_ id: CGWindowID, on s: Screen?) {
        let name = windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "This window"
        HUD.shared.warn("\(name) can't get any smaller", on: s?.ns)
    }

    func tiled(on s: Screen) -> [CGWindowID] {
        order.filter { visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[s.uuid] }
    }

    func usableRect(_ s: Screen) -> CGRect {
        var r = s.visible
        if config.ignoreMenuBar { r = CGRect(x: r.minX, y: s.frame.minY, width: r.width, height: r.maxY - s.frame.minY) }
        if config.disablePaddingOnBuiltinDisplay && s.isBuiltin { return r }
        return CGRect(x: r.minX + config.paddingLeft, y: r.minY + config.paddingTop,
                      width: r.width - config.paddingLeft - config.paddingRight,
                      height: r.height - config.paddingTop - config.paddingBottom)
    }

    func state(for s: Screen) -> ScreenState {
        state(workspace: shown[s.uuid] ?? "\(s.uuid):\(Spaces.current(display: s.uuid))")
    }

    func state(workspace key: String) -> ScreenState {
        if let st = states[key] { return st }
        let st = ScreenState(layout: config.layouts.first ?? .tall)
        states[key] = st
        return st
    }


    func screen(containing r: CGRect, in screens: [Screen] = Screen.all()) -> Screen? {
        guard !r.isNull else { return screens.first }
        return screens.max { a, b in
            let ia = a.frame.intersection(r), ib = b.frame.intersection(r)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    func screen(of w: Window, in screens: [Screen] = Screen.all()) -> Screen? {
        if config.virtualWorkspaces || !w.isFloating, let u = workspaceOf[w.id].flatMap({ monitorOf[$0] }),
           let s = screens.first(where: { $0.uuid == u }) { return s }
        return screen(containing: w.frame, in: screens)
    }

    var focusedScreen: NSScreen? { currentScreen()?.ns }

    func currentScreen() -> Screen? {
        let screens = Screen.all()
        if let w = focusedWindow(), let s = screen(of: w, in: screens) { return s }
        let p = mouseLocation()
        return screens.first { $0.frame.contains(p) } ?? screens.first
    }

    func focusedWindowState() -> (floating: Bool, fullscreen: Bool)? {
        guard let w = focusedWindow() else { return nil }
        let zoomed = screen(of: w).map { state(for: $0).zoomed == w.id } ?? false
        return (w.isFloating, zoomed)
    }

    func focusedWindow() -> Window? {
        if let p = pendingFocus {
            if Date() < p.until, let w = windows[p.id], visible.contains(p.id) { return w }
            pendingFocus = nil
        }
        return reportedFocusedWindow()
    }

    func reportedFocusedWindow() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { return nil }
        return windows[id]
    }

    func navFrame(_ w: Window) -> CGRect {
        (!w.isFloating && tilingEnabled ? targets[w.id] : nil) ?? w.frame
    }

    func relation(_ f: CGRect, _ of: CGRect, _ dir: Direction) -> (along: CGFloat, across: CGFloat, overlaps: Bool, edge: CGFloat) {
        let dx = of.midX - f.midX, dy = of.midY - f.midY
        let rows = of.minY < f.maxY && of.maxY > f.minY, cols = of.minX < f.maxX && of.maxX > f.minX
        switch dir {
        case .left: return (-dx, dy, rows, f.minX - of.maxX)
        case .right: return (dx, dy, rows, of.minX - f.maxX)
        case .up: return (-dy, dx, cols, f.minY - of.maxY)
        case .down: return (dy, dx, cols, of.minY - f.maxY)
        }
    }

    func neighbor(of w: Window, _ dir: Direction, among candidates: [Window]) -> Window? {
        let f = navFrame(w)
        let screens = Screen.all()
        let home = screen(of: w, in: screens)?.uuid
        var scored: [(w: Window, score: CGFloat, edge: CGFloat)] = []
        for o in candidates where o.id != w.id {
            let (along, across, overlaps, edge) = relation(f, navFrame(o), dir)
            guard along > 1 else { continue }
            guard overlaps || screen(of: o, in: screens)?.uuid != home else { continue }
            scored.append((o, along + abs(across) * 2 + (overlaps ? 0 : 100_000), overlaps ? max(0, edge) : .infinity))
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        guard let nearest = scored.map(\.edge).min(), nearest.isFinite else { return best.w }
        let adjacent = scored.filter { $0.edge <= nearest + 2 }
        let recent = adjacent.max { (focusStamps[$0.w.id] ?? 0) < (focusStamps[$1.w.id] ?? 0) }
        if let recent, focusStamps[recent.w.id] != nil { return recent.w }
        return adjacent.min(by: { $0.score < $1.score })?.w ?? best.w
    }

    func screen(from s: Screen, spec: String, in screens: [Screen]) -> Screen? {
        if let dir = Direction(spec) {
            let c = s.center
            return screens.filter { o in
                switch dir {
                case .left: o.center.x < c.x - 1
                case .right: o.center.x > c.x + 1
                case .up: o.center.y < c.y - 1
                case .down: o.center.y > c.y + 1
                }
            }.min { hypot($0.center.x - c.x, $0.center.y - c.y) < hypot($1.center.x - c.x, $1.center.y - c.y) }
        }
        let i = screens.firstIndex { $0.uuid == s.uuid } ?? 0
        if spec.hasPrefix("+") || spec.hasPrefix("-"), let d = Int(spec) {
            return screens[((i + d) % screens.count + screens.count) % screens.count]
        }
        if let n = Int(spec), screens.indices.contains(n) { return screens[n] }
        return nil
    }
}
