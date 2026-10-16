// Tiling: refresh loop that tiles windows into layout slots, plus screen and neighbor geometry.
import AppKit

extension WindowManager {
    // MARK: - Refresh & tiling

    /// Relayouts moving more windows than this land at once instead of animating (see `refresh`).
    static let maxAnimatedMoves = 6

    /// Coalesces refresh requests. A pending earlier refresh is kept rather than pushed back, so a
    /// steady stream of events can't postpone tiling indefinitely.
    func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scanAndRefresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    /// Reads every app's windows off the main thread (see `WindowScanner`), then refreshes with them.
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

    /// Discovers and prunes windows with the last scan's results, then lays out. It makes no AX reads
    /// on the main thread: frames come from `Window.cachedFrame`. `scheduleRefresh` scans again first.
    /// `placing` limits the frame writes to those windows; the rest keep their frames until the next refresh.
    func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        guard isStarted else { return }
        if scanner.lastScan == 0 { scheduleRefresh(after: 0) } // nothing scanned yet
        let screens = Screen.all()
        guard !screens.isEmpty else { return }

        // 1. Discover windows on the current space(s).
        let onScreen = CGWindowInfo.onScreen()
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let firstRun = windows.isEmpty
        // While macOS slides between Spaces, windows of the Space being left are still listed on screen.
        // Counting them would file them under the Space arriving and tile them there.
        let currentSpaces = Set(screens.map { Spaces.current(display: $0.uuid) })
        func onOtherSpace(_ id: CGWindowID) -> Bool {
            let spaces = Spaces.of(window: id)
            return !spaces.isEmpty && currentSpaces.isDisjoint(with: spaces)
        }
        var present = Set<CGWindowID>()
        var fresh: [Window] = []
        var titles: [CGWindowID: String?] = [:] // of the fresh windows, as the scan read them

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            observe(app)
            let pid = app.processIdentifier
            guard pidsOnScreen.contains(pid), let scan = scanner.results[pid] else { continue }
            for id in scan.listed {
                // A bridged move can become discoverable before its completion commits the
                // destination workspace. Do not tile that intermediate state as a new arrival.
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
        // An import in progress already belongs to its destination workspace (see `moveWindow`).
        present.formUnion(workspaceMoves.filter { windows[$0] != nil })

        // Front-most first, so on launch the window you were using becomes main.
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
        if !fresh.isEmpty { scheduleRefresh(after: 0.4) } // second pass for apps that reposition after opening

        // 2. Prune closed windows; keep ones that are merely on another space, minimized or hidden.
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
        // A new window may be why the old one closed (a dialog, a replacement): let it keep focus.
        if let ws = refocusAfterClose {
            refocusAfterClose = nil
            if fresh.isEmpty { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.refocusRecent(on: ws) } }
        }

        // 3. Lay out each screen.
        guard tilingEnabled else { onChange?(); return }
        var moves: [Animator.Move] = [], instant: [Animator.Move] = []
        for s in screens {
            let st = state(for: s)
            let ids = tiled(on: s)
            // Not while it's only out of sight for a moment (app hidden, minimised, mid Space switch).
            if let z = st.zoomed, windows[z]?.isFloating != false || workspaceOf[z] != shown[s.uuid] { st.zoomed = nil }
            guard let slots = layoutTargets(ids, st, on: s) else {
                ids.forEach { targets[$0] = nil } // floating layout: navigate by where windows really are
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
                // Already heading there: asking again would restart the curve at full speed.
                if animator.isMoving(id, to: target) { continue }
                if animator.isBusy(id) { moves.append(.init(window: w, to: target, bounds: s.visible)); continue }
                // Don't fight an app that keeps refusing the same frame (minimum size etc.).
                var c = corrections[id] ?? (target, 0)
                if c.target != target { c = (target, 0) }
                c.count += 1
                corrections[id] = c
                if c.count > 3 { continue }
                moves.append(.init(window: w, to: target, bounds: s.visible))
            }
        }
        if !moves.isEmpty { Log.debug("tile: moving \(moves.map { "\($0.window.id)→\($0.to)" }.joined(separator: ", "))") }
        animator.animate(instant, duration: 0) // windows that don't slide in with a workspace swap snap into place
        // An animated move costs AX calls on every frame for every window in it. With a crowd of
        // windows that keeps the main thread busy enough to stall events, so a big relayout lands at once.
        let animated = !instantLayout && config.animate && moves.count <= Self.maxAnimatedMoves
        animator.animate(moves, duration: animated ? config.animationDuration : 0,
                         curve: config.animationCurve, bounce: config.animationBounce)
        onChange?()
    }

    /// After the focused window closes, macOS hands focus to whatever it likes (often another
    /// column, or the app's other window). Like Hyprland, go back to the window used before it.
    private func refocusRecent(on ws: String) {
        guard isShown(ws), pendingFocus == nil else { return }
        // A dialog or other window we don't manage took focus: leave it be.
        if let app = NSWorkspace.shared.frontmostApplication,
           let id = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID,
           windows[id] == nil { return }
        let here = visible.filter { workspaceOf[$0] == ws }
        guard let id = model.mostRecent(of: here), reportedFocusedWindow()?.id != id, let w = windows[id] else { return }
        Log.debug("focus: window closed; back to \(id)")
        focus(w)
    }

    /// The frame each of `ids` (tiled windows in tiling order) gets on `s` with the workspace state `st`:
    /// its layout slot fitted around known minimum sizes, or the whole tiling area when zoomed.
    /// Nil for the floating layout. Every tiling of windows (refresh, staging, mouse resize) uses this.
    func layoutTargets(_ ids: [CGWindowID], _ st: ScreenState, on s: Screen) -> [CGWindowID: CGRect]? {
        guard let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else { return nil }
        let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
        let zoomed = usableRect(s).pixelAligned
        return Dictionary(zip(ids, slots).map { id, slot in (id, id == st.zoomed ? zoomed : slot) }, uniquingKeysWith: { a, _ in a })
    }

    /// The gap between `count` tiled windows: none for a lone window with smart margins.
    func windowGap(count: Int) -> CGFloat {
        config.windowMargins && !(config.smartWindowMargins && count == 1) ? config.windowMarginSize : 0
    }

    /// Each window's slot before fitting around minimum sizes, and the gap between windows.
    func rawSlots(_ ids: [CGWindowID], on s: Screen, _ st: ScreenState, ratio: CGFloat) -> ([CGRect], CGFloat)? {
        let gap = windowGap(count: ids.count)
        // Lay out in a rect grown by half a gap, then shrink every slot by half a gap: windows get
        // a full gap between them and sit exactly on the padding at the screen edges.
        guard let raw = st.layout.frames(count: ids.count, in: usableRect(s).insetBy(dx: -gap / 2, dy: -gap / 2),
                                         ratio: ratio, mainCount: st.mainCount) else { return nil }
        let slots = raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned }
        // A non-finite slot (bad display geometry mid-reconfiguration) must never reach the AX calls.
        guard slots.allSatisfy({ [$0.minX, $0.minY, $0.width, $0.height].allSatisfy(\.isFinite) }) else { return nil }
        return (slots, gap)
    }

    /// The first window whose known minimum size the new ratio squeezes further than the old one did.
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

    /// The workspace a display shows, which keys its layout state. Before `syncWorkspaces` has run
    /// for the display, that is the workspace of its current macOS Space, as `syncWorkspaces` names it.
    func workspaceKey(for s: Screen) -> String {
        shown[s.uuid] ?? Self.spaceWorkspace(display: s.uuid, space: Spaces.current(display: s.uuid))
    }

    func state(workspace key: String) -> ScreenState {
        if let st = states[key] { return st }
        let st = ScreenState(layout: config.layouts.first ?? .tall)
        states[key] = st
        return st
    }

    // MARK: - Geometry helpers

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

    /// The screen with the focused window, else the one under the pointer.
    var focusedScreen: NSScreen? { currentScreen()?.ns }

    func currentScreen() -> Screen? {
        let screens = Screen.all()
        if let w = focusedWindow(), let s = screen(of: w, in: screens) { return s }
        let p = mouseLocation()
        return screens.first { $0.frame.contains(p) } ?? screens.first
    }

    /// The focused window's floating and fullscreen state, for the menu's toggles.
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

    /// The focused window as macOS reports it, which lags behind `focus(_:)`.
    func reportedFocusedWindow() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { return nil }
        return windows[id]
    }

    /// Frame used for navigation: the tile slot when tiled (stable even mid-animation), else the real frame.
    func navFrame(_ w: Window) -> CGRect {
        (!w.isFloating && tilingEnabled ? targets[w.id] : nil) ?? w.frame
    }

    /// `w` as focus navigation sees it (see `FocusNavigation`).
    func navItem(_ w: Window, in screens: [Screen]) -> FocusNavigation.Item {
        .init(id: w.id, frame: navFrame(w), screen: screen(of: w, in: screens)?.uuid)
    }

    /// The window to go to from `w` in direction `dir` (see `FocusNavigation.neighbor`).
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
