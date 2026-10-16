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

    func windowGap(count: Int) -> CGFloat {
        config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0
    }

    func rawSlots(_ ids: [CGWindowID], on s: Screen, _ st: ScreenState, ratio: CGFloat) -> ([CGRect], CGFloat)? {
        let gap = windowGap(count: ids.count)
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
        state(workspace: workspaceKey(for: s))
    }

    func workspaceKey(for s: Screen) -> String {
        shown[s.uuid] ?? Self.spaceWorkspace(display: s.uuid, space: Spaces.current(display: s.uuid))
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

    func navItem(_ w: Window, in screens: [Screen]) -> FocusNavigation.Item {
        .init(id: w.id, frame: navFrame(w), screen: screen(of: w, in: screens)?.uuid)
    }

    func neighbor(of w: Window, _ dir: Direction, among candidates: [Window]) -> Window? {
        let screens = Screen.all()
        let id = FocusNavigation.neighbor(of: navItem(w, in: screens), dir,
                                          among: candidates.map { navItem($0, in: screens) }, stamps: focusStamps)
        return id.flatMap { windows[$0] }
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
