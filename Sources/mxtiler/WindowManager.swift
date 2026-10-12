import AppKit

enum Direction {
    case left, right, up, down
    init?(_ s: String) {
        switch s.lowercased() {
        case "l", "left": self = .left
        case "r", "right": self = .right
        case "u", "up", "t", "top": self = .up
        case "d", "down", "b", "bottom": self = .down
        default: return nil
        }
    }
}

final class ScreenState {
    var layout: Layout
    var ratio: CGFloat = 0.5
    var mainCount = 1
    var zoomed: CGWindowID?
    init(layout: Layout) { self.layout = layout }
}

let ipcNotification = Notification.Name("local.mxtiler.command")

private final class FocusSinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
                        _ refcon: UnsafeMutableRawPointer?) {
    WindowManager.shared.handle(notification as String, element)
}

final class WindowManager {
    static let shared = WindowManager()

    private(set) var config = Config.load()
    private(set) var tilingEnabled = true
    var onChange: (() -> Void)?

    private var windows: [CGWindowID: Window] = [:]
    private var order: [CGWindowID] = []            // tiling order; first window on a screen is "main"
    // Workspaces. In virtual mode these are mxtiler's own (windows on hidden workspaces are parked
    // off-screen); in macOS-Spaces mode each display's current Space is treated as its workspace.
    private var workspaceOf: [CGWindowID: String] = [:] // workspace each window belongs to
    private var monitorOf: [String: String] = [:]        // display UUID each workspace lives on
    private var shown: [String: String] = [:]            // display UUID → workspace it shows right now
    private var virtualShown: [String: String] = [:]     // display UUID → mxtiler workspace on its home Space
    private var homeSpace: [String: UInt64] = [:]        // display UUID → the macOS Space workspaces live on
    private var present: Set<CGWindowID> = []
    private var lastFocused: [String: CGWindowID] = [:]
    private var lastClose = Date.distantPast // when a window last closed (macOS then refocuses the previous app's window)
    private var floatFrames: [CGWindowID: CGRect] = [:]  // floating windows' frames while parked
    private var savedWorkspaceOf: [CGWindowID: String] = [:]
    private var savedOwnerOf: [CGWindowID: String] = [:]  // "pid bundleID" when saved; window IDs are reused after a logout
    private var previousWorkspace: [String: String] = [:] // display UUID → workspace it showed before
    private var autoSwitchAfter = Date.distantPast
    private var lastSavedWorkspaces = ""
    private var focusSink: NSWindow?
    private var visible: Set<CGWindowID> = []       // managed windows on the current space(s)
    private var targets: [CGWindowID: CGRect] = [:] // slot each tiled window was last given
    private var states: [String: ScreenState] = [:] // per workspace
    private var observers: [pid_t: AXObserver] = [:]
    private var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    private var drags: [CGWindowID: Bool] = [:]     // window -> was resized (vs. only moved)
    private var refreshWork: DispatchWorkItem?
    private var ffmWork: DispatchWorkItem?
    private var minSizes: [CGWindowID: CGSize] = [:] // learned from windows that refuse to shrink
    private var refreshDeadline = DispatchTime.distantFuture
    private(set) var isStarted = false
    private var ignoreMouseUntil = Date.distantPast
    private var movingToSpace = false
    /// Where an in-flight space switch is heading. macOS keeps reporting the old space until the
    /// slide finishes, so quick repeated presses must count from here or they overshoot.
    private var pendingSpace: (display: String, index: Int, until: Date)?
    private var spaceGeneration = 0
    private let animator = Animator()

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        Log.verbose = config.debugLogging
        Log.info("start: trusted=\(AXIsProcessTrusted()) windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(Screen.all().count)")
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0) // a hung app can't freeze us
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            for delay in [0.3, 1.0, 2.5] { // apps take a moment before AX answers
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.observe(app); self?.scheduleRefresh() }
            }
        }
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let pid = app.processIdentifier
            if let obs = observers[pid] { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode) }
            observers[pid] = nil
            windows.values.filter { $0.pid == pid }.forEach { self.forget($0.id) }
            scheduleRefresh()
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() }
        }
        // ⌘-Tab or a Dock click onto a window on a hidden workspace switches to that workspace.
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.followFocus() }
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            scheduleRefresh(after: 0.15)
            if !config.virtualWorkspaces, config.enablesLayoutHUDOnSpaceChange, config.enablesLayoutHUD, let s = currentScreen() {
                HUD.shared.show(state(for: s).layout.title, on: s.ns)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh(after: 0.4) }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() }
        // Clicking somewhere means you've moved on: leave any mode, like vim leaving normal mode.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in
            if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        }
        Hotkeys.shared.onSubmapChange = { [weak self] name in
            ModeIndicator.shared.show(name.isEmpty ? nil : name)
            Log.debug("mode: \(name.isEmpty ? "reset" : name)")
            self?.onChange?()
        }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in self?.mouseMoved() }

        Hotkeys.shared.setBindings(config.bindings)
        Hotkeys.shared.handler = { [weak self] b in self?.dispatch(b.dispatcher, b.arg) }
        if !Hotkeys.shared.start() {
            Log.info("start: could not create the keyboard event tap")
            HUD.shared.show("Keybinds unavailable: grant Accessibility", on: nil)
        }

        // `mxtiler dispatch movefocus l`, `mxtiler dump`, `mxtiler reload` from a terminal (like hyprctl).
        DistributedNotificationCenter.default().addObserver(forName: ipcNotification, object: nil, queue: .main) { [weak self] n in
            if let cmd = n.object as? String { self?.ipc(cmd) }
        }

        refresh()
        // Apps that were already running don't send a launch notification, and some (especially
        // at login) don't answer AX yet. Look again a few times so their windows still get tiled.
        for delay in [0.5, 1.5, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.scheduleRefresh() }
        }
    }

    func reload(showHUD: Bool = true) {
        let wasVirtual = config.virtualWorkspaces
        config = Config.load()
        if wasVirtual != config.virtualWorkspaces {
            if wasVirtual { restoreHiddenWindows() }
            workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]; states = [:]; lastFocused = [:]
            Log.info("workspaces: \(config.virtualWorkspaces ? "mxtiler workspaces" : "macOS Spaces")")
        }
        Log.verbose = config.debugLogging
        config.errors.forEach { Log.info("config: \($0)") }
        Hotkeys.shared.setBindings(config.bindings)
        for w in windows.values { w.autoFloating = shouldFloat(w) }
        corrections = [:]
        refresh()
        guard showHUD else { return }
        HUD.shared.show(config.errors.isEmpty ? "Config reloaded" : "Config: \(config.errors.count) error(s), see Console",
                        on: currentScreen()?.ns)
    }

    func toggleTiling() {
        tilingEnabled.toggle()
        HUD.shared.show(tilingEnabled ? "Tiling On" : "Tiling Off", on: currentScreen()?.ns)
        refresh()
    }

    var currentLayoutTitle: String {
        guard let s = currentScreen() else { return "" }
        return state(for: s).layout.title
    }

    // MARK: - Observing apps

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, pid != getpid(), observers[pid] == nil else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, axCallback, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
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

    private func watch(_ w: Window) {
        guard let obs = observers[w.pid] else { return }
        for n in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                  kAXWindowDeminiaturizedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, w.element, n as CFString, nil)
        }
    }

    fileprivate func handle(_ notification: String, _ element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            lastClose = Date()
            scheduleRefresh()
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = element.windowID, let w = windows[id], !animator.isBusy(id), !movingToSpace else { return }
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

    private func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
        let old = minSizes[id] ?? .zero
        let new = CGSize(width: max(old.width, size.width.rounded()), height: max(old.height, size.height.rounded()))
        guard new != old else { return }
        minSizes[id] = new
        corrections[id] = nil
        Log.info("window \(id) has a minimum size of \(Int(new.width))×\(Int(new.height)); re-tiling around it")
        scheduleRefresh()
    }

    private func forget(_ id: CGWindowID) {
        windows[id] = nil
        order.removeAll { $0 == id }
        workspaceOf[id] = nil; floatFrames[id] = nil; targets[id] = nil; minSizes[id] = nil; corrections[id] = nil; drags[id] = nil
        visible.remove(id)
    }

    private func shouldFloat(_ w: Window) -> Bool {
        // Our own windows (Settings, guides) always float, even when another copy of mxtiler
        // (a dev build, or the old Hyprthyst) is the one tiling.
        if let b = w.bundleID, b == Bundle.main.bundleIdentifier || b.hasPrefix("local.mxtiler") || b == "local.hyprthyst" {
            return true
        }
        if let b = w.bundleID {
            let listed = config.floating.contains { pattern in
                pattern.hasSuffix("*") ? b.hasPrefix(String(pattern.dropLast())) : b == pattern
            }
            if config.floatingIsBlacklist ? listed : !listed { return true }
        } else if !config.floatingIsBlacklist {
            return true
        }
        if !w.element.isSettable(kAXSizeAttribute) { return true } // fixed-size windows can't tile
        let f = w.naturalFrame
        if config.floatSmallWindows, !f.isNull, f.width < 500, f.height < 500 { return true }
        return false
    }

    // MARK: - Refresh & tiling

    /// Coalesces refresh requests. A pending earlier refresh is kept rather than pushed back, so a
    /// steady stream of events can't postpone tiling indefinitely.
    func scheduleRefresh(after delay: Double = 0.05) {
        let deadline = DispatchTime.now() + delay
        if refreshWork != nil, refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        refreshDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: work)
    }

    func refresh() {
        refreshWork?.cancel(); refreshWork = nil
        guard isStarted else { return }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }

        // 1. Discover windows on the current space(s).
        let onScreen = CGWindowInfo.onScreen()
        let onScreenIDs = Set(onScreen.map(\.id))
        let pidsOnScreen = Set(onScreen.map(\.pid))
        let firstRun = windows.isEmpty
        var present = Set<CGWindowID>()
        var fresh: [Window] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            observe(app)
            let pid = app.processIdentifier
            guard pidsOnScreen.contains(pid) else { continue }
            for el in AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute) {
                guard let id = el.windowID, onScreenIDs.contains(id) else { continue }
                if let w = windows[id] {
                    if !w.isNativeFullscreen { present.insert(id) }
                    continue
                }
                guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      el.bool(kAXMinimizedAttribute) != true, el.bool("AXFullScreen") != true else { continue }
                let w = Window(id: id, element: el, pid: pid, bundleID: app.bundleIdentifier)
                w.naturalFrame = el.frame
                w.autoFloating = shouldFloat(w)
                windows[id] = w
                watch(w)
                fresh.append(w)
                present.insert(id)
            }
        }

        // Front-most first, so on launch the window you were using becomes main.
        let z = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let arrivals = fresh.sorted(by: { (z[$0.id] ?? 0) < (z[$1.id] ?? 0) })
        for w in arrivals where config.virtualWorkspaces {
            if let saved = savedWorkspaceOf[w.id], savedOwnerOf[w.id] == owner(w) { workspaceOf[w.id] = saved }
        }
        if config.newWindowsToMain && !firstRun { order.insert(contentsOf: arrivals.map(\.id), at: 0) } else { order.append(contentsOf: arrivals.map(\.id)) }
        for w in fresh {
            Log.debug("new window \(w.id) \(w.bundleID ?? "pid \(w.pid)") floating=\(w.isFloating) frame=\(w.frame)")
        }
        if !fresh.isEmpty { scheduleRefresh(after: 0.4) } // second pass for apps that reposition after opening

        // 2. Prune closed windows; keep ones that are merely on another space, minimized or hidden.
        for (id, w) in windows where !present.contains(id) {
            if NSRunningApplication(processIdentifier: w.pid) == nil || !w.isValid { forget(id) }
        }
        self.present = present
        syncWorkspaces(screens: screens, present: present)
        visible = present.filter { isShown(workspaceOf[$0]) }
        if config.virtualWorkspaces {
            for id in present where !visible.contains(id) { park(id, screens: screens) }
            for id in visible where windows[id]?.isFloating == true { unpark(floating: id, screens: screens) }
            saveWorkspaces()
        }

        // 3. Lay out each screen.
        guard tilingEnabled else { onChange?(); return }
        var moves: [Animator.Move] = [], instant: [Animator.Move] = []
        for s in screens {
            let st = state(for: s)
            let ids = tiled(on: s)
            if let z = st.zoomed, !ids.contains(z) { st.zoomed = nil }
            let rect = usableRect(s)
            let gap = config.windowMargins && !(config.smartWindowMargins && ids.count == 1) ? config.windowMarginSize : 0
            // Lay out in a rect grown by half a gap, then shrink every slot by half a gap: windows get
            // a full gap between them and sit exactly on the padding at the screen edges.
            guard let raw = st.layout.frames(count: ids.count, in: rect.insetBy(dx: -gap / 2, dy: -gap / 2),
                                             ratio: st.ratio, mainCount: st.mainCount) else { continue }
            let slots = fitMinimums(raw.map { $0.insetBy(dx: gap / 2, dy: gap / 2).pixelAligned },
                                    mins: ids.map { minSizes[$0] }, gap: gap)
            for (id, slot) in zip(ids, slots) {
                let target = id == st.zoomed ? rect.pixelAligned : slot
                targets[id] = target
                guard let w = windows[id] else { continue }
                let current = w.frame
                if current.isNull || current.approxEqual(target) { corrections[id] = nil; continue }
                if isParked(current, screens) { instant.append(.init(window: w, to: target, bounds: s.visible)); continue }
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
        animator.animate(instant, duration: 0) // workspace switches are instant, like Hyprland
        animator.animate(moves, duration: config.animate ? config.animationDuration : 0)
        onChange?()
    }

    private func tiled(on s: Screen) -> [CGWindowID] {
        order.filter { visible.contains($0) && windows[$0]?.isFloating == false && workspaceOf[$0] == shown[s.uuid] }
    }

    private func usableRect(_ s: Screen) -> CGRect {
        var r = s.visible
        if config.ignoreMenuBar { r = CGRect(x: r.minX, y: s.frame.minY, width: r.width, height: r.maxY - s.frame.minY) }
        if config.disablePaddingOnBuiltinDisplay && s.isBuiltin { return r }
        return CGRect(x: r.minX + config.paddingLeft, y: r.minY + config.paddingTop,
                      width: r.width - config.paddingLeft - config.paddingRight,
                      height: r.height - config.paddingTop - config.paddingBottom)
    }

    private func state(for s: Screen) -> ScreenState {
        state(workspace: shown[s.uuid] ?? "\(s.uuid):\(Spaces.current(display: s.uuid))")
    }

    private func state(workspace key: String) -> ScreenState {
        if let st = states[key] { return st }
        let st = ScreenState(layout: config.layouts.first ?? .tall)
        states[key] = st
        return st
    }

    // MARK: - Geometry helpers

    private func screen(containing r: CGRect, in screens: [Screen] = Screen.all()) -> Screen? {
        guard !r.isNull else { return screens.first }
        return screens.max { a, b in
            let ia = a.frame.intersection(r), ib = b.frame.intersection(r)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        }
    }

    private func screen(of w: Window, in screens: [Screen] = Screen.all()) -> Screen? {
        if config.virtualWorkspaces || !w.isFloating, let u = workspaceOf[w.id].flatMap({ monitorOf[$0] }),
           let s = screens.first(where: { $0.uuid == u }) { return s }
        return screen(containing: w.frame, in: screens)
    }

    private func currentScreen() -> Screen? {
        let screens = Screen.all()
        if let w = focusedWindow(), let s = screen(of: w, in: screens) { return s }
        let p = mouseLocation()
        return screens.first { $0.frame.contains(p) } ?? screens.first
    }

    private func focusedWindow() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { return nil }
        return windows[id]
    }

    /// Frame used for navigation: the tile slot when tiled (stable even mid-animation), else the real frame.
    private func navFrame(_ w: Window) -> CGRect {
        (!w.isFloating && tilingEnabled ? targets[w.id] : nil) ?? w.frame
    }

    private func neighbor(of w: Window, _ dir: Direction, among candidates: [Window]) -> Window? {
        let f = navFrame(w)
        var best: (Window, CGFloat)?
        for o in candidates where o.id != w.id {
            let of = navFrame(o)
            let dx = of.midX - f.midX, dy = of.midY - f.midY
            let (along, across, overlaps): (CGFloat, CGFloat, Bool)
            switch dir {
            case .left: (along, across, overlaps) = (-dx, dy, of.minY < f.maxY && of.maxY > f.minY)
            case .right: (along, across, overlaps) = (dx, dy, of.minY < f.maxY && of.maxY > f.minY)
            case .up: (along, across, overlaps) = (-dy, dx, of.minX < f.maxX && of.maxX > f.minX)
            case .down: (along, across, overlaps) = (dy, dx, of.minX < f.maxX && of.maxX > f.minX)
            }
            guard along > 1 else { continue }
            let score = along + abs(across) * 2 + (overlaps ? 0 : 100_000)
            if best == nil || score < best!.1 { best = (o, score) }
        }
        return best?.0
    }

    private func screen(from s: Screen, spec: String, in screens: [Screen]) -> Screen? {
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

    // MARK: - Focus & mouse

    private func focus(_ w: Window) {
        w.focus()
        if config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            CGWarpMouseCursorPosition(navFrame(w).center)
        }
    }

    /// Focus follows mouse fires once the pointer rests for a moment, so sweeping across several
    /// windows doesn't raise each one, and the window under the final position always gets focus.
    private func mouseMoved() {
        guard config.focusFollowsMouse else { return }
        ffmWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.focusUnderMouse() }
        ffmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    private func focusUnderMouse() {
        guard config.focusFollowsMouse, Date() > ignoreMouseUntil, NSEvent.pressedMouseButtons == 0, !movingToSpace else { return }
        let p = mouseLocation()
        guard let hit = CGWindowInfo.normalWindow(at: p), let w = windows[hit.id], visible.contains(w.id),
              focusedWindow()?.id != w.id else { return }
        Log.debug("ffm: focusing \(w.id) \(w.bundleID ?? "")")
        w.focus()
    }

    private func mouseUp() {
        guard !drags.isEmpty, !movingToSpace else { drags = [:]; return }
        let finished = drags
        drags = [:]
        let screens = Screen.all()
        let p = mouseLocation()
        for (id, resized) in finished {
            guard let w = windows[id], !w.isFloating, let src = screen(of: w, in: screens) else { continue }
            if resized {
                if config.mouseResizesWindows { applyMouseResize(w, on: src) }
                continue
            }
            let dst = screens.first { $0.frame.contains(p) } ?? src
            if config.mouseSwapsWindows,
               let hit = tiled(on: dst).first(where: { $0 != id && targets[$0]?.contains(p) == true }) {
                swapOrder(id, hit)
            } else if dst.uuid != src.uuid {
                workspaceOf[id] = shown[dst.uuid]
            }
        }
        corrections = [:]
        refresh()
    }

    /// Turn a mouse resize of a tiled window into a new main-pane ratio.
    private func applyMouseResize(_ w: Window, on s: Screen) {
        let st = state(for: s)
        let ids = tiled(on: s)
        let r = usableRect(s), f = w.frame
        let mains = [.bsp, .twoPane, .twoPaneRight].contains(st.layout) ? 1 : st.mainCount
        guard let idx = ids.firstIndex(of: w.id), ids.count > mains, var axis = st.layout.ratioAxis else { return }
        if st.layout == .bsp { axis = (r.width >= r.height, true) }
        let isMain = idx < mains
        if st.layout == .widescreenTall, isMain, mains > 1, idx != mains - 1 { return }
        if st.layout == .widescreenTallRight, isMain, mains > 1, idx != 0 { return }
        if !isMain, [.threeColumnLeft, .threeColumnRight].contains(st.layout) { return }
        let gap = config.windowMargins ? config.windowMarginSize : 0
        let total = axis.horizontal ? r.width : r.height
        let boundary: CGFloat // distance of the main/secondary edge from the main pane's outer side
        switch (axis.horizontal, axis.fromStart, isMain) {
        case (true, true, true): boundary = f.maxX - r.minX + gap
        case (true, true, false): boundary = f.minX - r.minX
        case (true, false, true): boundary = r.maxX - f.minX + gap
        case (true, false, false): boundary = r.maxX - f.maxX
        case (false, _, true): boundary = f.maxY - r.minY + gap
        case (false, _, false): boundary = f.minY - r.minY
        }
        st.ratio = min(0.9, max(0.1, boundary / (total + gap)))
    }

    // MARK: - Status & IPC

    struct Status {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var tiled: Int
        var floating: Int
        var screens: [(uuid: String, name: String, layout: Layout, workspace: String)]
    }

    func status() -> Status {
        let screens = Screen.all()
        let managed = visible.compactMap { windows[$0] }
        return Status(trusted: AXIsProcessTrusted(), keybindsActive: Hotkeys.shared.isActive, running: isStarted,
                      tilingEnabled: tilingEnabled,
                      launchAtLogin: LoginItem.isEnabled, loginNeedsApproval: LoginItem.needsApproval,
                      tiled: managed.filter { !$0.isFloating }.count, floating: managed.filter(\.isFloating).count,
                      screens: isStarted ? screens.map { ($0.uuid, $0.ns.localizedName, state(for: $0).layout,
                                                           isVirtual(shown[$0.uuid]) ? (shown[$0.uuid] ?? "") : "") } : [])
    }

    func setLayout(_ l: Layout, screen uuid: String) {
        guard let s = Screen.all().first(where: { $0.uuid == uuid }) else { return }
        let st = state(for: s)
        st.layout = l
        st.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(l.title, on: s.ns) }
    }

    private func ipc(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 2).map(String.init)
        Log.info("ipc: \(command)")
        switch parts.first {
        case "dispatch" where parts.count >= 2:
            // exec is refused here: any process, sandboxed or not, can post this notification.
            guard parts[1].lowercased() != "exec" else { Log.info("ipc: exec is only allowed from keybinds"); return }
            dispatch(parts[1].lowercased(), parts.count > 2 ? parts[2] : "")
        case "dump": dumpState()
        case "grabtest": grabTest()
        case "poststyle" where parts.count >= 2:
            // Diagnostics: `mxtiler poststyle 0|1|2` picks how synthetic shortcuts are sent.
            if let n = Int(parts[1]), let style = Hotkeys.PostStyle(rawValue: n) { Hotkeys.postStyle = style }
            Log.info("ipc: post style is now \(Hotkeys.postStyle)")
        case "reload": reload()
        default: Log.info("ipc: unknown command")
        }
    }

    private func dumpState() {
        var lines = ["state: trusted=\(AXIsProcessTrusted()) keybinds=\(Hotkeys.shared.isActive) tiling=\(tilingEnabled) focused=\(focusedWindow()?.id ?? 0)"]
        for s in Screen.all() {
            let st = state(for: s)
            lines.append("  screen \(s.ns.localizedName) workspace=\(shown[s.uuid] ?? "?") home=\(isOnHomeSpace(s)) layout=\(st.layout.rawValue) ratio=\(st.ratio) main=\(st.mainCount) usable=\(usableRect(s))")
            for id in tiled(on: s) {
                let w = windows[id]!
                let ok = targets[id].map { w.frame.approxEqual($0, tolerance: 2) } ?? false
                lines.append("    tiled \(id) \(w.bundleID ?? "pid \(w.pid)") target=\(targets[id] ?? .null) actual=\(w.frame) \(ok ? "OK" : "MISMATCH")")
            }
        }
        for id in visible where windows[id]?.isFloating == true {
            lines.append("  floating \(id) \(windows[id]!.bundleID ?? "") \(windows[id]!.frame)")
        }
        for (id, ws) in workspaceOf.sorted(by: { $0.value < $1.value }) where present.contains(id) && !visible.contains(id) {
            lines.append("  parked \(id) \(windows[id]?.bundleID ?? "") workspace=\(ws) frame=\(windows[id]?.frame ?? .null)")
        }
        lines.forEach { Log.info($0) }
    }

    // MARK: - Commands

    private func swapOrder(_ a: CGWindowID, _ b: CGWindowID) {
        guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return }
        order.swapAt(i, j)
        (workspaceOf[a], workspaceOf[b]) = (workspaceOf[b], workspaceOf[a])
    }

    func dispatch(_ dispatcher: String, _ rawArg: String) {
        let arg = rawArg.trimmingCharacters(in: .whitespaces)
        switch dispatcher {
        case "movefocus": if let d = Direction(arg) { moveFocus(d) }
        case "movewindow":
            if arg.lowercased().hasPrefix("mon:") { moveToMonitor(String(arg.dropFirst(4))) }
            else if let d = Direction(arg) { moveWindow(d) }
        case "swapwindow": if let d = Direction(arg) { moveWindow(d) }
        case "cyclenext": cycleFocus(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "swapnext": cycleSwap(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layoutmsg": layoutMessage(arg)
        case "splitratio": adjustRatio(arg)
        case "togglefloating": toggleFloating()
        case "fullscreen": toggleZoom()
        case "killactive": lastClose = Date(); focusedWindow()?.close()
        case "exec": exec(arg)
        case "focusmonitor": focusMonitor(arg)
        case "movewindowtomonitor": moveToMonitor(arg)
        case "workspace":
            if config.virtualWorkspaces { if let ws = resolveWorkspace(arg) { showWorkspace(ws) } }
            else if let n = Int(arg) { switchSpace(n) }
        case "movetoworkspace", "movetoworkspacesilent":
            if config.virtualWorkspaces {
                if let ws = resolveWorkspace(arg) { moveFocusedWindow(to: ws, follow: dispatcher == "movetoworkspace") }
            } else if let n = Int(arg) { moveToSpace(n) }
        case "cyclelayout": cycleLayout(arg.lowercased().hasPrefix("prev") ? -1 : 1)
        case "layout", "setlayout": if let l = Layout(rawValue: arg.lowercased()) { setLayout(l) }
        case "toggletiling": toggleTiling()
        case "submap": Hotkeys.shared.setSubmap(arg)
        case "sethomespace": makeCurrentSpaceHome()
        case "retile", "reevaluate": corrections = [:]; refresh()
        case "reload": reload()
        case "exit": NSApp.terminate(nil)
        default: NSLog("mxtiler: unknown dispatcher %@", dispatcher)
        }
    }

    private func layoutMessage(_ arg: String) {
        let parts = arg.split(separator: " ").map(String.init)
        guard let cmd = parts.first?.lowercased() else { return }
        switch cmd {
        case "swapwithmaster": swapWithMain()
        case "focusmaster": focusMain()
        case "addmaster": changeMainCount(1)
        case "removemaster": changeMainCount(-1)
        case "cyclenext": cycleFocus(1)
        case "cycleprev": cycleFocus(-1)
        case "swapnext": cycleSwap(1)
        case "swapprev": cycleSwap(-1)
        case "mfact": adjustRatio(parts.dropFirst().joined(separator: " "))
        case "orientationnext": cycleLayout(1)
        case "orientationprev": cycleLayout(-1)
        default: NSLog("mxtiler: unknown layoutmsg %@", cmd)
        }
    }

    /// Windows on the focused screen in tiling order, plus the focused window and its screen.
    private func context() -> (w: Window?, s: Screen, st: ScreenState, ids: [CGWindowID])? {
        guard let s = currentScreen() else { return nil }
        return (focusedWindow(), s, state(for: s), tiled(on: s))
    }

    private func moveFocus(_ d: Direction) {
        guard let w = focusedWindow() else {
            if let c = context(), let first = c.ids.first.flatMap({ windows[$0] }) { focus(first) }
            return
        }
        let candidates = visible.compactMap { windows[$0] }
        if let n = neighbor(of: w, d, among: candidates) { focus(n); return }
        // Stacked layouts (fullscreen / zoom / two-pane) have no geometry to navigate: cycle instead.
        cycleFocus(d == .left || d == .up ? -1 : 1)
    }

    private func moveWindow(_ d: Direction) {
        guard let w = focusedWindow(), !w.isFloating else { return }
        let candidates = visible.compactMap { windows[$0] }.filter { !$0.isFloating }
        if let n = neighbor(of: w, d, among: candidates) {
            if let a = screen(of: w), let b = screen(of: n), a.uuid != b.uuid {
                workspaceOf[w.id] = shown[b.uuid] // across monitors Hyprland moves without swapping
            } else {
                swapOrder(w.id, n.id)
            }
        } else if let src = screen(of: w), let dst = screen(from: src, spec: arg(d), in: Screen.all()) {
            workspaceOf[w.id] = shown[dst.uuid] // nothing that way on this screen: hop to the next monitor
        } else { return }
        refresh()
        focus(w)
    }

    private func arg(_ d: Direction) -> String {
        switch d { case .left: "l"; case .right: "r"; case .up: "u"; case .down: "d" }
    }

    private func cycleFocus(_ delta: Int) {
        guard let c = context(), !c.ids.isEmpty else { return }
        let i = c.w.flatMap { c.ids.firstIndex(of: $0.id) } ?? (delta > 0 ? -1 : 0)
        let next = c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count]
        if let w = windows[next] { focus(w) }
    }

    private func cycleSwap(_ delta: Int) {
        guard let c = context(), let w = c.w, let i = c.ids.firstIndex(of: w.id), c.ids.count > 1 else { return }
        swapOrder(w.id, c.ids[((i + delta) % c.ids.count + c.ids.count) % c.ids.count])
        refresh()
    }

    private func swapWithMain() {
        guard let c = context(), let w = c.w, c.ids.count > 1, c.ids.contains(w.id) else { return }
        swapOrder(w.id, c.ids[0] == w.id ? c.ids[1] : c.ids[0])
        refresh()
        focus(w)
    }

    private func focusMain() {
        guard let c = context(), let id = c.ids.first, let w = windows[id] else { return }
        focus(w)
    }

    private func changeMainCount(_ delta: Int) {
        guard let c = context() else { return }
        c.st.mainCount = max(1, min(10, c.st.mainCount + delta))
        refresh()
    }

    /// "+0.05", "-0.05", "0.05" (relative) or "exact 0.6".
    private func adjustRatio(_ arg: String) {
        guard let c = context() else { return }
        let parts = arg.lowercased().split(separator: " ")
        if parts.first == "exact", parts.count > 1, let v = Double(parts[1]) {
            c.st.ratio = CGFloat(v)
        } else {
            let delta = Double(arg.replacingOccurrences(of: "+", with: "")).map { CGFloat($0) } ?? config.windowResizeStep
            c.st.ratio += delta
        }
        c.st.ratio = min(0.9, max(0.1, c.st.ratio))
        refresh()
    }

    private func toggleFloating() {
        guard let w = focusedWindow() else { return }
        w.userFloating = !w.isFloating
        if w.isFloating {
            targets[w.id] = nil
        } else {
            if let s = screen(containing: w.frame) { workspaceOf[w.id] = shown[s.uuid] }
            corrections[w.id] = nil
        }
        refresh()
    }

    /// Hyprland's `fullscreen`: the window covers the whole tiling area until toggled again.
    private func toggleZoom() {
        guard let c = context(), let w = c.w, c.ids.contains(w.id) else { return }
        c.st.zoomed = c.st.zoomed == w.id ? nil : w.id
        refresh()
        w.focus()
    }

    private func cycleLayout(_ delta: Int) {
        guard let c = context(), !config.layouts.isEmpty else { return }
        let i = config.layouts.firstIndex(of: c.st.layout) ?? -1
        setLayout(config.layouts[((i + delta) % config.layouts.count + config.layouts.count) % config.layouts.count])
    }

    private func setLayout(_ l: Layout) {
        guard let c = context() else { return }
        c.st.layout = l
        c.st.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(l.title, on: c.s.ns) }
    }

    private func exec(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }

    private func focusMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let src = currentScreen(), let dst = screen(from: src, spec: spec, in: screens) else { return }
        // Prefer the topmost managed window on that screen, else its main window.
        let p = CGWindowInfo.onScreen().first { info in
            guard visible.contains(info.id), let w = windows[info.id] else { return false }
            return screen(of: w, in: screens)?.uuid == dst.uuid
        }
        if let id = p?.id ?? tiled(on: dst).first, let w = windows[id] {
            focus(w)
        } else {
            CGWarpMouseCursorPosition(dst.center)
        }
    }

    private func moveToMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let w = focusedWindow(), let src = screen(of: w, in: screens),
              let dst = screen(from: src, spec: spec, in: screens), dst.uuid != src.uuid else { return }
        if w.isFloating {
            let f = w.frame
            var o = CGPoint(x: dst.visible.minX + (f.minX - src.visible.minX), y: dst.visible.minY + (f.minY - src.visible.minY))
            o.x = max(dst.visible.minX, min(o.x, dst.visible.maxX - f.width))
            o.y = max(dst.visible.minY, min(o.y, dst.visible.maxY - f.height))
            animator.animate([.init(window: w, to: CGRect(origin: o, size: f.size), bounds: dst.visible)],
                             duration: config.animate ? config.animationDuration : 0)
            workspaceOf[w.id] = shown[dst.uuid]
            scheduleRefresh()
        } else {
            workspaceOf[w.id] = shown[dst.uuid]
            refresh()
        }
        focus(w)
    }

    // MARK: - mxtiler workspaces

    private func isShown(_ ws: String?) -> Bool { ws.map { Set(shown.values).contains($0) } ?? false }

    /// Workspaces sort numerically first ("2" before "10"), then by name.
    private func workspaceSort(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    var currentWorkspace: String? { currentScreen().flatMap { virtualShown[$0.uuid] } }

    /// Workspaces with windows or on screen, for the menu bar indicator.
    func workspaceSummary() -> (current: String?, all: [(name: String, windows: Int, shown: Bool)]) {
        guard config.virtualWorkspaces, isStarted else { return (nil, []) }
        var counts: [String: Int] = [:]
        for (id, ws) in workspaceOf where windows[id] != nil && isVirtual(ws) { counts[ws, default: 0] += 1 }
        let names = Set(counts.keys).union(virtualShown.values).sorted(by: workspaceSort)
        let showing = Set(virtualShown.values)
        let current = currentScreen().flatMap { virtualShown[$0.uuid] }
        return (current, names.map { ($0, counts[$0] ?? 0, showing.contains($0)) })
    }

    private func firstFreeWorkspace() -> String {
        let used = Set(workspaceOf.values).union(virtualShown.values).filter(isVirtual)
        var n = 1
        while used.contains(String(n)) { n += 1 }
        return String(n)
    }

    /// `3`, `name:web`, `previous`, `+1`/`-1` (by number), `e+1`/`e-1` (next/previous with windows).
    private func resolveWorkspace(_ raw: String) -> String? {
        let a = raw.trimmingCharacters(in: .whitespaces)
        let lower = a.lowercased()
        let cur = currentWorkspace ?? "1"
        if a.isEmpty { return nil }
        if lower == "previous" { return currentScreen().flatMap { previousWorkspace[$0.uuid] } }
        if lower.hasPrefix("name:") { return String(a.dropFirst(5)) }
        for prefix in ["r", "m", ""] where lower.hasPrefix(prefix + "+") || lower.hasPrefix(prefix + "-") {
            guard let d = Int(lower.dropFirst(prefix.count).replacingOccurrences(of: "+", with: "")) else { break }
            return String(max(1, (Int(cur) ?? 1) + d))
        }
        if lower.hasPrefix("e+") || lower.hasPrefix("e-"), let d = Int(lower.dropFirst(1).replacingOccurrences(of: "+", with: "")) {
            let occupied = Set(workspaceOf.values).union(virtualShown.values).filter(isVirtual).sorted(by: workspaceSort)
            guard !occupied.isEmpty else { return nil }
            let i = occupied.firstIndex(of: cur) ?? 0
            return occupied[((i + d) % occupied.count + occupied.count) % occupied.count]
        }
        return a
    }

    /// Keeps workspace bookkeeping consistent with the displays that exist. In macOS-Spaces mode,
    /// mirrors whatever Space each display is showing.
    private func isVirtual(_ ws: String?) -> Bool { ws.map { !$0.hasPrefix("space:") } ?? false }

    /// Keeps workspace bookkeeping consistent with the displays that exist.
    ///
    /// mxtiler workspaces live on one "home" macOS Space per display. On any other Space a
    /// display behaves like macOS-Spaces mode: that Space is its workspace and nothing is parked,
    /// so having several macOS Spaces can't scramble anything.
    private func syncWorkspaces(screens: [Screen], present: Set<CGWindowID>) {
        let uuids = Set(screens.map(\.uuid))
        for u in shown.keys where !uuids.contains(u) { shown[u] = nil }
        for u in virtualShown.keys where !uuids.contains(u) { virtualShown[u] = nil }
        if config.virtualWorkspaces {
            // A display that went away hands its workspaces to the first remaining one, like Hyprland.
            for (ws, m) in monitorOf where isVirtual(ws) && !uuids.contains(m) { monitorOf[ws] = screens[0].uuid }
        }
        var onHome = Set<String>()
        for s in screens {
            let space = Spaces.current(display: s.uuid)
            if config.virtualWorkspaces {
                if let home = homeSpace[s.uuid], let ids = Spaces.list(display: s.uuid)?.ids, !ids.isEmpty, !ids.contains(home) {
                    homeSpace[s.uuid] = nil // that Space was removed
                }
                if homeSpace[s.uuid] == nil { homeSpace[s.uuid] = space }
            }
            if config.virtualWorkspaces && space == homeSpace[s.uuid] {
                if virtualShown[s.uuid] == nil {
                    let own = monitorOf.filter { $0.value == s.uuid && isVirtual($0.key) && !virtualShown.values.contains($0.key) }
                        .map(\.key).sorted(by: workspaceSort).first
                    virtualShown[s.uuid] = own ?? firstFreeWorkspace()
                }
                shown[s.uuid] = virtualShown[s.uuid]
                onHome.insert(s.uuid)
            } else {
                shown[s.uuid] = "space:\(s.uuid):\(space)"
            }
            monitorOf[shown[s.uuid]!] = s.uuid
        }
        // A window we can see but whose workspace isn't showing is either parked (a mxtiler
        // workspace whose display is on its home Space) or has moved between macOS Spaces, in
        // which case it joins whatever is showing where it is now.
        for id in present where !isShown(workspaceOf[id]) {
            let ws = workspaceOf[id]
            if isVirtual(ws), let m = ws.flatMap({ monitorOf[$0] }), onHome.contains(m) { continue }
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            workspaceOf[id] = shown[s.uuid]
        }
        for id in present where workspaceOf[id] == nil {
            guard let w = windows[id] else { continue }
            let s = screen(containing: w.frame, in: screens) ?? screens[0]
            workspaceOf[id] = shown[s.uuid]
        }
    }

    /// Makes the macOS Space each display is showing now the one mxtiler workspaces live on.
    func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        for s in Screen.all() {
            homeSpace[s.uuid] = Spaces.current(display: s.uuid)
            if !isVirtual(virtualShown[s.uuid]) { virtualShown[s.uuid] = nil }
        }
        // Windows here join the workspace that's now showing instead of a per-Space one.
        workspaceOf = workspaceOf.filter { isVirtual($0.value) }
        refresh()
        HUD.shared.show("mxtiler workspaces live on this Desktop", on: currentScreen()?.ns)
    }

    var homeSpaceSummary: String {
        guard config.virtualWorkspaces else { return "" }
        let names = Screen.all().compactMap { s -> String? in
            guard let home = homeSpace[s.uuid], let info = Spaces.list(display: s.uuid),
                  let i = info.ids.firstIndex(of: home), let d = info.desktops.firstIndex(of: i) else { return nil }
            return "Desktop \(d + 1)" + (Screen.all().count > 1 ? " on \(s.ns.localizedName)" : "")
        }
        return names.joined(separator: ", ")
    }

    /// Is this display currently showing its home Space (where mxtiler workspaces live)?
    private func isOnHomeSpace(_ s: Screen) -> Bool {
        guard let home = homeSpace[s.uuid] else { return true }
        return Spaces.current(display: s.uuid) == home
    }

    // Parking: hidden workspaces' windows sit in a display corner with a 1px sliver showing,
    // since macOS won't let a window go fully off-screen.

    private func isParked(_ f: CGRect, _ screens: [Screen]) -> Bool {
        guard !f.isNull, f.width > 0, f.height > 0 else { return false }
        let onScreen = screens.reduce(CGFloat(0)) { sum, s in
            let i = s.frame.intersection(f)
            return sum + (i.isNull ? 0 : i.width * i.height)
        }
        return onScreen < 400
    }

    /// Bottom-right corner of the window's display, or bottom-left if another display sits to the right.
    private func parkingSpot(size: CGSize, on s: Screen, _ screens: [Screen]) -> CGPoint {
        let right = CGPoint(x: s.frame.maxX - 1, y: s.frame.maxY - 1)
        let left = CGPoint(x: s.frame.minX - size.width + 1, y: s.frame.maxY - 1)
        for o in [right, left] {
            let r = CGRect(origin: o, size: size)
            if !screens.contains(where: { $0.uuid != s.uuid && $0.frame.intersects(r) }) { return o }
        }
        return right
    }

    private func park(_ id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id], isVirtual(workspaceOf[id]) else { return }
        let f = w.frame
        guard !f.isNull, !isParked(f, screens) else { return }
        let s = workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { u in screens.first { $0.uuid == u } } ?? screens[0]
        if w.isFloating { floatFrames[id] = f }
        animator.cancel(id)
        animator.quiet(id)
        EnhancedUI.suspend(w.pid)
        w.setPosition(parkingSpot(size: f.size, on: s, screens))
        EnhancedUI.resume(w.pid)
    }

    private func unpark(floating id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id] else { return }
        let f = w.frame
        guard isParked(f, screens) else { floatFrames[id] = nil; return }
        let s = screen(of: w, in: screens) ?? screens[0]
        var r = floatFrames.removeValue(forKey: id)
            ?? CGRect(x: s.visible.midX - f.width / 2, y: s.visible.midY - f.height / 2, width: f.width, height: f.height)
        r.origin.x = max(s.visible.minX, min(r.origin.x, s.visible.maxX - r.width))
        r.origin.y = max(s.visible.minY, min(r.origin.y, s.visible.maxY - r.height))
        animator.quiet(id)
        EnhancedUI.suspend(w.pid)
        w.setFrame(r)
        EnhancedUI.resume(w.pid)
    }

    /// Puts every parked window back on screen. Called when quitting, when killed, and when
    /// switching back to macOS Spaces, so nothing is ever left stranded in a corner.
    func restoreHiddenWindows() {
        guard config.virtualWorkspaces || !shown.isEmpty else { return }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        saveWorkspaces()
        for (id, w) in windows {
            let f = w.frame
            guard isParked(f, screens) else { continue }
            let s = screen(of: w, in: screens) ?? screens[0]
            var r = floatFrames[id] ?? targets[id]
                ?? CGRect(x: s.visible.midX - f.width / 2, y: s.visible.midY - f.height / 2, width: f.width, height: f.height)
            r.size.width = min(r.width, s.visible.width)
            r.size.height = min(r.height, s.visible.height)
            r.origin.x = max(s.visible.minX, min(r.origin.x, s.visible.maxX - r.width))
            r.origin.y = max(s.visible.minY, min(r.origin.y, s.visible.maxY - r.height))
            EnhancedUI.suspend(w.pid)
            w.setFrame(r)
            EnhancedUI.resume(w.pid)
        }
        Log.info("workspaces: put parked windows back on screen")
    }

    private func loadWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let d = UserDefaults.standard
        for (k, v) in d.dictionary(forKey: "ws.windows") as? [String: String] ?? [:] {
            if let id = CGWindowID(k) { savedWorkspaceOf[id] = v }
        }
        for (k, v) in d.dictionary(forKey: "ws.owners") as? [String: String] ?? [:] {
            if let id = CGWindowID(k) { savedOwnerOf[id] = v }
        }
        monitorOf = d.dictionary(forKey: "ws.monitors") as? [String: String] ?? [:]
        virtualShown = d.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (k, v) in d.dictionary(forKey: "ws.home") as? [String: NSNumber] ?? [:] { homeSpace[k] = v.uint64Value }
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    private func owner(_ w: Window) -> String { "\(w.pid) \(w.bundleID ?? "")" }

    private func saveWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let windowsMap = Dictionary(workspaceOf.filter { windows[$0.key] != nil && isVirtual($0.value) }.map { (String($0.key), $0.value) },
                                    uniquingKeysWith: { a, _ in a })
        let monitors = monitorOf.filter { isVirtual($0.key) }
        let key = "\(windowsMap.sorted { $0.key < $1.key })|\(monitors.sorted { $0.key < $1.key })|\(virtualShown.sorted { $0.key < $1.key })|\(homeSpace.sorted { $0.key < $1.key })"
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let d = UserDefaults.standard
        d.set(windowsMap, forKey: "ws.windows")
        d.set(Dictionary(windowsMap.keys.compactMap { k in CGWindowID(k).flatMap { windows[$0] }.map { (k, owner($0)) } },
                         uniquingKeysWith: { a, _ in a }), forKey: "ws.owners")
        d.set(monitors, forKey: "ws.monitors")
        d.set(virtualShown, forKey: "ws.shown")
        d.set(homeSpace.mapValues { NSNumber(value: $0) }, forKey: "ws.home")
    }

    /// Hyprland's `workspace`: shows it on its display (a new one opens on the focused display)
    /// and focuses the window you last used there.
    func showWorkspace(_ ws: String, focusing preferred: Window? = nil, attempts: Int = 3) {
        let screens = Screen.all()
        guard let here = currentScreen() ?? screens.first else { return }
        let monitor = monitorOf[ws].flatMap { u in screens.first { $0.uuid == u } } ?? here
        if let cur = virtualShown[monitor.uuid], cur != ws { previousWorkspace[monitor.uuid] = cur }
        monitorOf[ws] = monitor.uuid
        virtualShown[monitor.uuid] = ws
        autoSwitchAfter = Date().addingTimeInterval(0.6)
        // On another macOS Space? Go to the home Space first, then show the workspace there.
        if !isOnHomeSpace(monitor), let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
           let index = info.ids.firstIndex(of: home), let desktop = info.desktops.firstIndex(of: index) {
            guard attempts > 0 else { Log.info("workspaces: couldn't reach the home Space for \(ws)"); return }
            CGWarpMouseCursorPosition(monitor.center) // space switching acts on the display under the pointer
            guard let steps = goToSpace(desktop + 1) else { Log.info("workspaces: can't switch Spaces for \(ws)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.15 * Double(steps)) { [weak self] in
                self?.showWorkspace(ws, focusing: preferred, attempts: attempts - 1)
            }
            return
        }
        shown[monitor.uuid] = ws
        Log.debug("workspaces: showing \(ws) on \(monitor.ns.localizedName)")
        refresh()
        let candidates = [preferred?.id, lastFocused[ws]].compactMap { $0 } + order + Array(visible)
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == ws }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
            if config.mouseFollowsFocus { CGWarpMouseCursorPosition(monitor.center) }
        }
        onChange?()
    }

    /// Hyprland's `movetoworkspace` (follow) and `movetoworkspacesilent`.
    private func moveFocusedWindow(to ws: String, follow: Bool) {
        guard let w = focusedWindow(), let from = workspaceOf[w.id], from != ws else { return }
        guard isVirtual(from) else {
            HUD.shared.show("Move this window to your mxtiler Desktop first", on: screen(of: w)?.ns)
            return
        }
        if monitorOf[ws] == nil, let here = currentScreen() { monitorOf[ws] = here.uuid }
        workspaceOf[w.id] = ws
        lastFocused[ws] = w.id
        if lastFocused[from] == w.id { lastFocused[from] = nil }
        corrections[w.id] = nil
        if follow {
            showWorkspace(ws, focusing: w)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            if let next = order.first(where: { workspaceOf[$0] == from && visible.contains($0) }).flatMap({ windows[$0] }) {
                focus(next)
            } else {
                parkFocus()
            }
        }
    }

    /// If the focused window lives on a hidden workspace (⌘-Tab, Dock, a link opening a window),
    /// switch to it. Also remembers each workspace's last focused window.
    private func followFocus() {
        guard config.virtualWorkspaces, isStarted, let w = focusedWindow(), let ws = workspaceOf[w.id], isVirtual(ws) else { return }
        if isShown(ws) { lastFocused[ws] = w.id; return }
        guard Date() > autoSwitchAfter else { return }
        // Only a window we actually parked means "go to its workspace". One you can already see
        // (e.g. on another macOS Desktop, not yet re-filed) just needs a refresh.
        guard isParked(w.frame, Screen.all()) else { scheduleRefresh(); return }
        if config.stayOnWorkspaceAfterClose, Date().timeIntervalSince(lastClose) < 1.0 {
            // A window just closed and macOS handed focus to one on another workspace: stay put.
            Log.debug("workspaces: ignoring focus on \(ws) right after a close")
            refocusCurrentWorkspace()
            return
        }
        Log.info("workspaces: \(w.bundleID ?? "a window") on workspace \(ws) was focused; switching")
        showWorkspace(ws, focusing: w)
    }

    /// Focuses the last-used window on the workspace showing on the current display, or parks focus.
    private func refocusCurrentWorkspace() {
        guard let s = currentScreen(), let cur = virtualShown[s.uuid] else { return parkFocus() }
        let candidates = [lastFocused[cur]].compactMap { $0 } + order
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == cur }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
        }
    }

    /// With nothing to focus, take keyboard focus ourselves so typing doesn't land in a window
    /// that's parked off-screen.
    private func parkFocus() {
        let sink = focusSink ?? {
            let w = FocusSinkWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                    styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.alphaValue = 0.01
            w.ignoresMouseEvents = true
            w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .stationary]
            focusSink = w
            return w
        }()
        if let primary = NSScreen.screens.first { sink.setFrameOrigin(NSPoint(x: 0, y: primary.frame.maxY - 1)) }
        sink.orderFrontRegardless()
        sink.makeKey()
        if !WindowServerFocus.focus(pid: getpid(), window: CGWindowID(sink.windowNumber)) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Spaces

    /// Goes to desktop `n` (1-based) on the display under the pointer. Uses "Switch to Desktop N" when
    /// it's turned on in Keyboard Shortcuts; otherwise steps there with "Move left/right a space",
    /// which macOS has on by default. Returns how many switches were posted, or nil on failure.
    @discardableResult
    private func goToSpace(_ n: Int, autoCorrect: Bool = true) -> Int? {
        if let combo = SystemShortcut.desktop(n) {
            Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags)
            pendingSpace = nil
            return 1
        }
        let screens = Screen.all()
        let p = mouseLocation()
        guard let s = screens.first(where: { $0.frame.contains(p) }) ?? currentScreen(),
              let info = Spaces.list(display: s.uuid), var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard n >= 1, n <= info.desktops.count else {
            HUD.shared.show("There is no space \(n)", on: s.ns)
            return nil
        }
        if let p = pendingSpace, p.display == s.uuid, Date() < p.until { cur = p.index }
        let delta = info.desktops[n - 1] - cur
        guard delta != 0 else { return 0 }
        guard let combo = SystemShortcut.step(right: delta > 0) else {
            HUD.shared.show("Turn on “Move left/right a space” in Keyboard Shortcuts", on: s.ns)
            return nil
        }
        Log.info("spaces: desktop \(cur + 1) → \(n), stepping \(delta) with key \(combo.keyCode) flags \(combo.flags.rawValue) style \(Hotkeys.postStyle)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = (s.uuid, info.desktops[n - 1], Date().addingTimeInterval(settle))
        spaceGeneration += 1
        let generation = spaceGeneration
        guard autoCorrect else { return abs(delta) }
        // macOS sometimes drops a step when presses reverse direction mid-slide. Once it settles,
        // check where we actually are and step the rest of the way (twice at most).
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: s.uuid, target: info.desktops[n - 1], generation: generation, attemptsLeft: 2)
        }
        return abs(delta)
    }

    private func switchSpace(_ n: Int) { goToSpace(n) }

    private func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
        guard generation == spaceGeneration, attemptsLeft > 0,
              let info = Spaces.list(display: display), let cur = info.current, cur != target,
              let combo = SystemShortcut.step(right: target > cur) else { return }
        let delta = target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = (display, target, Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: display, target: target, generation: generation, attemptsLeft: attemptsLeft - 1)
        }
    }

    // MARK: Moving windows between spaces

    /// macOS has no public (or, since 14.5, private) way to move another app's window to a space,
    /// so do what a person would: hold the window by an empty part of its title bar and switch
    /// spaces. The grab point is found by asking Accessibility what's under each candidate point,
    /// then confirmed by nudging the window and checking it followed.
    private func moveToSpace(_ n: Int) {
        guard !movingToSpace, let w = focusedWindow() else { return }
        let f = w.frame
        guard !f.isNull else { return }
        let points = grabPoints(for: w, frame: f)
        guard !points.isEmpty else {
            HUD.shared.show("This window has nothing to grab", on: screen(of: w)?.ns)
            Log.info("move to space: no grab point for \(w.bundleID ?? "pid \(w.pid)")")
            return
        }
        movingToSpace = true
        w.focus()
        tryGrab(w, points[...], space: n, restore: mouseLocation())
    }

    private func postMouse(_ type: CGEventType, _ p: CGPoint) {
        guard let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                              mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    /// Presses at `p` and drags gradually. Chromium-based apps only start a window drag after the
    /// pointer passes a threshold, so a tiny nudge isn't enough. Calls back with whether the window
    /// followed, and the point where the button is still held.
    private func attemptGrab(_ w: Window, at p: CGPoint, completion: @escaping (Bool, CGPoint) -> Void) {
        let before = serverFrame(w.id) ?? w.frame
        let offsets: [CGFloat] = [4, 12, 22]
        postMouse(.leftMouseDown, p)
        func step(_ k: Int) {
            guard k < offsets.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                    guard let self else { return }
                    let after = serverFrame(w.id) ?? w.frame
                    // Any frame change counts: dragging a window that fills the screen makes macOS
                    // restore its earlier size around the pointer, which can move it left.
                    let grabbed = !after.approxEqual(before, tolerance: 4)
                    Log.info("move to space: pressed \(w.bundleID ?? "pid \(w.pid)") at \(p); frame \(before) → \(after)")
                    completion(grabbed, CGPoint(x: p.x + offsets.last!, y: p.y))
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (k == 0 ? 0.05 : 0.025)) { [weak self] in
                self?.postMouse(.leftMouseDragged, CGPoint(x: p.x + offsets[k], y: p.y))
                step(k + 1)
            }
        }
        step(0)
    }

    private func tryGrab(_ w: Window, _ points: ArraySlice<CGPoint>, space n: Int, restore: CGPoint) {
        guard let p = points.first else {
            Log.info("move to space: couldn't grab \(w.bundleID ?? "pid \(w.pid)")")
            HUD.shared.show("Couldn't grab this window", on: screen(of: w)?.ns)
            finishMove(restore: restore)
            return
        }
        let original = serverFrame(w.id) ?? w.frame
        attemptGrab(w, at: p) { [weak self] grabbed, held in
            guard let self else { return }
            guard grabbed else {
                // Not a draggable spot: let go and try the next one.
                postMouse(.leftMouseUp, held)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.tryGrab(w, points.dropFirst(), space: n, restore: restore)
                }
                return
            }
            Log.info("move to space: holding \(w.bundleID ?? "pid \(w.pid)"), going to space \(n)")
            rememberGrab(w, p, frame: original)
            guard let steps = goToSpace(n, autoCorrect: false), steps > 0 else {
                postMouse(.leftMouseUp, held)
                finishMove(restore: restore)
                return
            }
            holdUntilArrived(space: n, release: held, restore: restore, waited: 0,
                             settle: 0.45 + 0.15 * Double(steps - 1), attemptsLeft: 2)
        }
    }

    /// Diagnostics (`mxtiler grabtest`): try each grab point on the focused window without
    /// switching spaces, logging which ones pick the window up.
    private func grabTest() {
        guard !movingToSpace, let w = focusedWindow() else { Log.info("grabtest: no focused window"); return }
        let points = grabPoints(for: w, frame: w.frame)
        Log.info("grabtest: \(w.bundleID ?? "pid \(w.pid)") frame \(w.frame) candidates \(points)")
        movingToSpace = true
        let restore = mouseLocation()
        func next(_ rest: ArraySlice<CGPoint>) {
            guard let p = rest.first else { finishMove(restore: restore); return }
            attemptGrab(w, at: p) { [weak self] grabbed, held in
                self?.postMouse(.leftMouseUp, held)
                Log.info("grabtest: \(p) \(grabbed ? "GRABS" : "no")")
                if grabbed { self?.rememberGrab(w, p, frame: w.frame) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { next(rest.dropFirst()) }
            }
        }
        next(points[...])
    }

    /// Keep holding the window until the switch has finished on the right space, correcting any
    /// step macOS dropped, then let go.
    private func holdUntilArrived(space n: Int, release: CGPoint, restore: CGPoint, waited: Double, settle: Double, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self else { return }
            let p = mouseLocation()
            if attemptsLeft > 0, let s = Screen.all().first(where: { $0.frame.contains(p) }),
               let info = Spaces.list(display: s.uuid), let cur = info.current, info.desktops.indices.contains(n - 1),
               cur != info.desktops[n - 1], let combo = SystemShortcut.step(right: info.desktops[n - 1] > cur) {
                let delta = info.desktops[n - 1] - cur
                Log.info("move to space: landed on \(cur + 1); stepping \(delta) more")
                for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
                holdUntilArrived(space: n, release: release, restore: restore, waited: waited + settle,
                                 settle: 0.45 + 0.15 * Double(abs(delta) - 1), attemptsLeft: attemptsLeft - 1)
                return
            }
            postMouse(.leftMouseUp, release)
            finishMove(restore: restore)
        }
    }

    private func finishMove(restore: CGPoint) {
        CGWarpMouseCursorPosition(restore)
        drags = [:]
        movingToSpace = false
        scheduleRefresh(after: 0.2)
    }

    /// The window server's idea of the frame; it updates during a title-bar drag before AX does.
    private func serverFrame(_ id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let b = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b)
    }

    /// Where a grab last worked for each app, measured from the window's top-left and top-right
    /// corners, so the next move tries it first.
    private lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = UserDefaults.standard.dictionary(forKey: "grabHints") as? [String: [Double]] ?? [:]
        return saved.compactMapValues { v in
            v.count == 4 ? (CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3])) : nil
        }
    }()

    private func rememberGrab(_ w: Window, _ p: CGPoint, frame f: CGRect) {
        guard let id = w.bundleID else { return }
        let hint = (CGPoint(x: p.x - f.minX, y: p.y - f.minY), CGPoint(x: f.maxX - p.x, y: p.y - f.minY))
        grabHints[id] = hint
        UserDefaults.standard.set(grabHints.mapValues { [Double($0.fromLeft.x), Double($0.fromLeft.y), Double($0.fromRight.x), Double($0.fromRight.y)] },
                                  forKey: "grabHints")
    }

    /// Candidate spots to hold a window by, best first: where it worked last time for this app,
    /// spots on the bare window background, then everything else along the top strip that isn't a
    /// control. Each one is still confirmed by a test drag.
    private func grabPoints(for w: Window, frame f: CGRect) -> [CGPoint] {
        var raw: [CGPoint] = []
        if let id = w.bundleID, let h = grabHints[id] {
            raw.append(CGPoint(x: f.minX + h.fromLeft.x, y: f.minY + h.fromLeft.y))
            raw.append(CGPoint(x: f.maxX - h.fromRight.x, y: f.minY + h.fromRight.y))
        }
        if let zoom = w.element.element(kAXZoomButtonAttribute)?.frame, !zoom.isNull {
            raw.append(CGPoint(x: zoom.maxX + 14, y: zoom.midY))
        }
        // Not the top few pixels: that's the resize border in apps that draw their own title bar.
        for dy: CGFloat in [9, 15, 22, 30] {
            var x = f.minX + 72
            while x < f.maxX - 30 {
                raw.append(CGPoint(x: x, y: f.minY + dy))
                x += 22
            }
        }
        let app = AXUIElementCreateApplication(w.pid)
        let blocked: Set<String> = [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXTextFieldRole, kAXTextAreaRole,
                                    kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole, kAXSliderRole, "AXLink",
                                    kAXIncrementorRole, "AXTab", kAXImageRole, kAXScrollAreaRole, "AXWebArea",
                                    kAXStaticTextRole, kAXMenuBarRole, kAXMenuItemRole]
        let background: Set<String> = [kAXWindowRole, kAXGroupRole, kAXToolbarRole, kAXUnknownRole, kAXSplitGroupRole, "AXTabGroup"]
        var best: [CGPoint] = [], ok: [CGPoint] = [], unknown: [CGPoint] = []
        var skipped: [String: Int] = [:]
        let hinted = grabHints[w.bundleID ?? ""] != nil ? 2 : 0
        var hintedCount = 0
        for (k, p) in raw.enumerated() where f.contains(p) {
            if k < hinted { best.append(p); hintedCount += 1; continue }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &hit) == .success, let hit else {
                unknown.append(p); continue
            }
            let role = hit.string(kAXRoleAttribute) ?? "?"
            if blocked.contains(role) { skipped[role, default: 0] += 1; continue }
            var actions: CFArray?
            if AXUIElementCopyActionNames(hit, &actions) == .success,
               let names = actions as? [String], names.contains(kAXPressAction) { skipped["\(role)+press", default: 0] += 1; continue }
            let owner = role == kAXWindowRole ? hit : hit.element(kAXWindowAttribute)
            if let owner, let oid = owner.windowID, oid != w.id { skipped["covered", default: 0] += 1; continue }
            if background.contains(role) { best.append(p) } else { ok.append(p) }
        }
        // Spread the picks out (neighbouring points usually hit the same element) and alternate
        // between the left and right ends, where the empty gaps in toolbars usually are.
        func spaced(_ ps: [CGPoint], _ limit: Int) -> [CGPoint] {
            var thin: [CGPoint] = []
            for p in ps where !thin.contains(where: { abs($0.x - p.x) < 30 && abs($0.y - p.y) < 6 }) { thin.append(p) }
            let sorted = thin.sorted { $0.x < $1.x }
            var out: [CGPoint] = []
            var lo = 0, hi = sorted.count - 1
            while lo <= hi && out.count < limit {
                out.append(sorted[lo]); lo += 1
                if lo <= hi && out.count < limit { out.append(sorted[hi]); hi -= 1 }
            }
            return out
        }
        let hintedPicks = Array(best[..<hintedCount])
        let rest = Array(best.dropFirst(hintedCount))
        let picks = Array((hintedPicks + spaced(rest, 14) + spaced(ok, 4) + spaced(unknown, 2)).prefix(20))
        Log.info("move to space: \(picks.count) grab candidates for \(w.bundleID ?? "pid \(w.pid)"); skipped \(skipped)")
        return picks
    }
}
