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

let ipcNotification = Notification.Name("local.ouch.command")

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
    /// Every command run (and whether a mode was on), and every mode change. The onboarding tour listens.
    var onDispatch: ((_ dispatcher: String, _ arg: String, _ inMode: Bool) -> Void)?
    var onModeChange: ((String) -> Void)?
    /// The onboarding tour's practice windows: their process, and the workspace each window title opens on.
    /// They come from a helper process because our own windows are never tiled.
    var practice: (pid: pid_t, workspaces: [String: String])?

    private var windows: [CGWindowID: Window] = [:]
    private var order: [CGWindowID] = []            // tiling order; first window on a screen is "main"
    // Workspaces. In virtual mode these are Ouch's own (windows on hidden workspaces are parked
    // off-screen); in macOS-Spaces mode each display's current Space is treated as its workspace.
    private var workspaceOf: [CGWindowID: String] = [:] // workspace each window belongs to
    private var monitorOf: [String: String] = [:]        // display UUID each workspace lives on
    private var shown: [String: String] = [:]            // display UUID → workspace it shows right now
    private var virtualShown: [String: String] = [:]     // display UUID → Ouch workspace on its home Space
    private var homeSpace: [String: UInt64] = [:]        // display UUID → the macOS Space workspaces live on
    private var workspaceMoves: Set<CGWindowID> = []
    private var snapNextPlacement: Set<CGWindowID> = []
    private var present: Set<CGWindowID> = []
    private var lastFocused: [String: CGWindowID] = [:]
    private var focusStamps: [CGWindowID: Int] = [:] // focus history: higher was focused more recently
    private var focusClock = 0
    /// A window we just focused. macOS takes a moment to report it, and a key press in between
    /// must navigate from it, not from the window before (or spamming a key goes nowhere).
    private var pendingFocus: (id: CGWindowID, until: Date)?
    private var refocusAfterClose: String? // workspace whose focused window just closed
    private var lastClose = Date.distantPast // when a window last closed (macOS then refocuses the previous app's window)
    private var floatFrames: [CGWindowID: CGRect] = [:]  // floating windows' frames while parked
    private var savedWorkspaceOf: [CGWindowID: String] = [:]
    private var savedOwnerOf: [CGWindowID: String] = [:]  // "pid bundleID" when saved; window IDs are reused after a logout
    private var savedFloating: [CGWindowID: Bool] = [:]  // windows floated or tiled by hand, from the last run
    private var previousWorkspace: [String: String] = [:] // display UUID → workspace it showed before
    private var labels: [String: String] = [:]           // workspace → the name the Sort panel gave it
    private var focusOrder: [CGWindowID] = []            // most recently focused first
    private var sortSnapshot: SortSnapshot?
    private var closingNow: Set<CGWindowID> = []          // closed by a finished sort, kept hidden until checked
    private var closingApps: Set<pid_t> = []              // apps of those windows, quit if the sort leaves them windowless
    /// The Sort panel is open: workspaces change under it, but nothing may take the keyboard or switch workspace.
    private var sortSession = false
    private var quietWorkspaceHUD = false
    /// A workspace swap in progress: leaving windows slide out, arriving ones slide in (see `beginSlide`).
    private struct Slide {
        let monitor: String           // display UUID the swap happens on
        let to: String                // workspace arriving
        let outgoing: Set<CGWindowID> // windows leaving
        let forward: Bool             // the new workspace sorts later: leaving windows go left, arriving ones come from the right
        let until: CFTimeInterval     // when the slide is done
    }
    private var slide: Slide?
    private var crowdWork: DispatchWorkItem?
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
    private var ratioChange: (screen: String, until: Date)? // a split resize whose windows are still settling
    private var refreshDeadline = DispatchTime.distantFuture
    private(set) var isStarted = false
    private var ignoreMouseUntil = Date.distantPast
    private var movingToSpace = false
    /// Where an in-flight space switch is heading. macOS keeps reporting the old space until the
    /// slide finishes, so quick repeated presses must count from here or they overshoot.
    private var pendingSpace: (display: String, index: Int, until: Date)?
    private var spaceGeneration = 0
    private let animator = Animator()
    private let dockWindowPull = DockWindowPull()
    private let dockArea = DockArea()

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        Log.verbose = config.debugLogging || Log.verboseLaunch
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
                HUD.shared.show(state(for: s).layout.title, layout: state(for: s).layout, on: s.ns)
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh(after: 0.4) }

        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.mouseUp() }
        // Clicking somewhere means you've moved on: leave any mode, like vim leaving normal mode.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.pendingFocus = nil // a click decides focus itself
            if !Hotkeys.shared.submap.isEmpty { Hotkeys.shared.setSubmap("") }
        }
        Hotkeys.shared.onSubmapChange = { [weak self] name in
            Log.debug("mode: \(name.isEmpty ? "reset" : name)")
            ModeFX.shared.setActive(!name.isEmpty)
            KeyHelp.shared.modeChanged(name)
            Tips.shared.modeChanged(name)
            self?.onChange?()
            self?.onModeChange?(name)
        }
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] e in
            if !CursorRefresh.isOurs(e) { self?.mouseMoved() }
        }

        Hotkeys.shared.setBindings(config.bindings)
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
        Hotkeys.shared.handler = { [weak self] b in self?.dispatch(b.dispatcher, b.arg) }
        KeyHelp.shared.install()
        if !Hotkeys.shared.start() {
            Log.info("start: could not create the keyboard event tap")
            HUD.shared.show("Keybinds unavailable: grant Accessibility", on: nil)
        }
        dockWindowPull.prepare = { [weak self] point in self?.prepareDockPull(at: point) }
        if dockWindowPull.start() { dockArea.refresh() } else { Log.info("Dock window import: mouse event tap unavailable") }

        // `ouch dispatch movefocus l`, `ouch dump`, `ouch reload` from a terminal (like hyprctl).
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
            labels = [:]; sortSnapshot = nil; closingNow = []; closingApps = []
            SortPanel.shared.abandon()
            Log.info("workspaces: \(config.virtualWorkspaces ? "Ouch workspaces" : "macOS Spaces")")
        }
        Log.verbose = config.debugLogging || Log.verboseLaunch
        ModeFX.shared.style = config.modeEffect
        FocusDim.shared.configure(dim: config.dimOtherWindows, strength: config.dimStrength,
                                  blur: config.blurOtherWindows, radius: Int(config.blurRadius))
        MacKeyboard.shared.setting = config.keyboardFinish
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
        HUD.shared.show(tilingEnabled ? "Tiling on" : "Tiling off", on: currentScreen()?.ns)
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

    private func learnMinimum(_ id: CGWindowID, _ size: CGSize) {
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

    private func forget(_ id: CGWindowID) {
        if focusClock > 0, focusStamps[id] == focusClock { refocusAfterClose = workspaceOf[id] }
        if pendingFocus?.id == id { pendingFocus = nil }
        windows[id] = nil
        snapNextPlacement.remove(id)
        order.removeAll { $0 == id }
        workspaceOf[id] = nil; floatFrames[id] = nil; targets[id] = nil; minSizes[id] = nil; corrections[id] = nil; drags[id] = nil
        focusStamps[id] = nil
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
    private func isUtilityWindow(_ w: Window) -> Bool {
        guard let title = w.element.string(kAXTitleAttribute), !title.isEmpty else { return false }
        if title == "Picture in Picture" || title == "Picture-in-Picture" { return true }
        if w.bundleID == "com.apple.finder" { return title.hasSuffix(" Info") }
        if let re = Self.signInTitle, re.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil { return true }
        let name = NSRunningApplication(processIdentifier: w.pid)?.localizedName
        let settings = ["Settings", "Preferences", "Settings…", "Preferences…"]
        return settings.contains(title) || name.map { n in settings.contains { title == "\(n) \($0)" } } == true
    }

    /// A mounted .dmg opens as a Finder window titled with its volume name ("drag to Applications").
    /// Disk images mount as ejectable volumes, so a Finder window named after one floats.
    private func isMountedImageWindow(_ w: Window) -> Bool {
        guard let title = w.element.string(kAXTitleAttribute), !title.isEmpty else { return false }
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsEjectableKey, .volumeIsInternalKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.contains { url in
            guard url.path != "/", let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return v.volumeName == title && (v.volumeIsEjectable == true || v.volumeIsInternal == false)
        }
    }

    private func shouldFloat(_ w: Window) -> Bool {
        if let p = practice, w.pid == p.pid { return false } // same bundle as us, but these are meant to tile
        // Our own windows (Settings, guides) always float, even when another copy of Ouch
        // (a dev build, or the old Hyprthyst) is the one tiling.
        if let b = w.bundleID, b == Bundle.main.bundleIdentifier || b.hasPrefix("local.ouch") || b == "local.hyprthyst" {
            return true
        }
        if let b = w.bundleID, Self.alwaysFloatingApps.contains(b) { return true }
        if w.bundleID == "com.apple.finder", isMountedImageWindow(w) { return true }
        if isUtilityWindow(w) { return true }
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

    /// Relayouts moving more windows than this land at once instead of animating (see `refresh`).
    private static let maxAnimatedMoves = 6

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

    /// `placing` limits the frame writes to those windows; the rest keep their frames until the next refresh.
    func refresh(instant instantLayout: Bool = false, placing only: Set<CGWindowID>? = nil) {
        refreshWork?.cancel(); refreshWork = nil
        guard isStarted else { return }
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

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            observe(app)
            let pid = app.processIdentifier
            guard pidsOnScreen.contains(pid) else { continue }
            for el in AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute) {
                // A bridged move can become discoverable before its completion commits the
                // destination workspace. Do not tile that intermediate state as a new arrival.
                guard let id = el.windowID, !workspaceMoves.contains(id),
                      onScreenIDs.contains(id), !onOtherSpace(id) else { continue }
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
        // An import in progress already belongs to its destination workspace (see `moveWindow`).
        present.formUnion(workspaceMoves.filter { windows[$0] != nil })

        // Front-most first, so on launch the window you were using becomes main.
        let z = Dictionary(onScreen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        let arrivals = fresh.sorted(by: { (z[$0.id] ?? 0) < (z[$1.id] ?? 0) })
        for w in arrivals where config.virtualWorkspaces {
            if savedOwnerOf[w.id] == owner(w) {
                if let saved = savedWorkspaceOf[w.id] { workspaceOf[w.id] = saved }
                if let float = savedFloating[w.id] { w.userFloating = float }
            }
            if let p = practice, w.pid == p.pid, let ws = w.element.string(kAXTitleAttribute).flatMap({ p.workspaces[$0] }) {
                workspaceOf[w.id] = ws
                if monitorOf[ws] == nil, let here = currentScreen() { monitorOf[ws] = here.uuid }
            }
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
            let rect = usableRect(s)
            guard let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else {
                ids.forEach { targets[$0] = nil } // floating layout: navigate by where windows really are
                continue
            }
            let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
            for (id, slot) in zip(ids, slots) {
                let target = id == st.zoomed ? rect.pixelAligned : slot
                targets[id] = target
                if let only, !only.contains(id) { continue }
                guard let w = windows[id] else { continue }
                let snap = snapNextPlacement.remove(id) != nil
                let current = w.frame
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
           let id = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute)?.windowID,
           windows[id] == nil { return }
        let here = visible.filter { workspaceOf[$0] == ws }
        guard let id = here.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }), focusStamps[id] != nil,
              reportedFocusedWindow()?.id != id, let w = windows[id] else { return }
        Log.debug("focus: window closed; back to \(id)")
        focus(w)
    }

    /// Each window's slot before fitting around minimum sizes, and the gap between windows.
    private func rawSlots(_ ids: [CGWindowID], on s: Screen, _ st: ScreenState, ratio: CGFloat) -> ([CGRect], CGFloat)? {
        let gap = config.windowMargins && !(config.smartWindowMargins && ids.count == 1) ? config.windowMarginSize : 0
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
    private func windowRefusingRatio(_ ratio: CGFloat, from old: CGFloat, ids: [CGWindowID], on s: Screen, _ st: ScreenState) -> CGWindowID? {
        guard ids.contains(where: { minSizes[$0] != nil }),
              let (before, _) = rawSlots(ids, on: s, st, ratio: old),
              let (after, _) = rawSlots(ids, on: s, st, ratio: ratio) else { return nil }
        return zip(ids, zip(before, after)).first { id, slots in
            guard let m = minSizes[id] else { return false }
            let (b, a) = slots
            return (m.width > a.width + 1 && a.width < b.width - 1) || (m.height > a.height + 1 && a.height < b.height - 1)
        }?.0
    }

    private func warnTooSmall(_ id: CGWindowID, on s: Screen?) {
        let name = windows[id].flatMap { NSRunningApplication(processIdentifier: $0.pid)?.localizedName } ?? "This window"
        HUD.shared.warn("\(name) can't get any smaller", on: s?.ns)
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

    /// The screen with the focused window, else the one under the pointer.
    var focusedScreen: NSScreen? { currentScreen()?.ns }

    private func currentScreen() -> Screen? {
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

    private func focusedWindow() -> Window? {
        if let p = pendingFocus {
            if Date() < p.until, let w = windows[p.id], visible.contains(p.id) { return w }
            pendingFocus = nil
        }
        return reportedFocusedWindow()
    }

    /// The focused window as macOS reports it, which lags behind `focus(_:)`.
    private func reportedFocusedWindow() -> Window? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = AXUIElementCreateApplication(app.processIdentifier).element(kAXFocusedWindowAttribute),
              let id = el.windowID else { return nil }
        return windows[id]
    }

    /// Frame used for navigation: the tile slot when tiled (stable even mid-animation), else the real frame.
    private func navFrame(_ w: Window) -> CGRect {
        (!w.isFloating && tilingEnabled ? targets[w.id] : nil) ?? w.frame
    }

    /// How `o` lies from `f` going `dir`: distance between centres along the way (negative when
    /// behind), offset across it, whether the two share a row/column, and the gap between near edges.
    private func relation(_ f: CGRect, _ of: CGRect, _ dir: Direction) -> (along: CGFloat, across: CGFloat, overlaps: Bool, edge: CGFloat) {
        let dx = of.midX - f.midX, dy = of.midY - f.midY
        let rows = of.minY < f.maxY && of.maxY > f.minY, cols = of.minX < f.maxX && of.maxX > f.minX
        switch dir {
        case .left: return (-dx, dy, rows, f.minX - of.maxX)
        case .right: return (dx, dy, rows, of.minX - f.maxX)
        case .up: return (-dy, dx, cols, f.minY - of.maxY)
        case .down: return (dy, dx, cols, of.minY - f.maxY)
        }
    }

    /// The window to go to from `w` in direction `dir`. On its own screen only windows sharing its
    /// row (left/right) or column (up/down) count, so up/down never drifts sideways. Like Hyprland,
    /// when several windows share the nearest edge that way (the stack beside a main window), the
    /// one you used last wins, so going left and back right returns to the window you started from.
    private func neighbor(of w: Window, _ dir: Direction, among candidates: [Window]) -> Window? {
        let f = navFrame(w)
        let screens = Screen.all()
        let home = screen(of: w, in: screens)?.uuid
        var scored: [(w: Window, score: CGFloat, edge: CGFloat)] = []
        for o in candidates where o.id != w.id {
            let (along, across, overlaps, edge) = relation(f, navFrame(o), dir)
            guard along > 1 else { continue }
            // Off the row/column is only allowed when crossing to another display.
            guard overlaps || screen(of: o, in: screens)?.uuid != home else { continue }
            scored.append((o, along + abs(across) * 2 + (overlaps ? 0 : 100_000), overlaps ? max(0, edge) : .infinity))
        }
        guard let best = scored.min(by: { $0.score < $1.score }) else { return nil }
        // Overlapping windows whose near edge is as close as the nearest one's are all adjacent.
        guard let nearest = scored.map(\.edge).min(), nearest.isFinite else { return best.w }
        let adjacent = scored.filter { $0.edge <= nearest + 2 }
        let recent = adjacent.max { (focusStamps[$0.w.id] ?? 0) < (focusStamps[$1.w.id] ?? 0) }
        if let recent, focusStamps[recent.w.id] != nil { return recent.w }
        return adjacent.min(by: { $0.score < $1.score })?.w ?? best.w
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
        noteFocus(w.id) // now, not when macOS gets round to telling us: quick key presses read it next
        pendingFocus = (w.id, Date().addingTimeInterval(0.5))
        if config.mouseFollowsFocus {
            ignoreMouseUntil = Date().addingTimeInterval(0.3)
            CGWarpMouseCursorPosition(navFrame(w).center)
        }
        CursorRefresh.soon() // the newly focused app sets its cursor only on a move
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

    private func noteFocus(_ id: CGWindowID) {
        focusClock += 1
        focusStamps[id] = focusClock
    }

    private func focusUnderMouse() {
        guard config.focusFollowsMouse, !sortSession, Date() > ignoreMouseUntil, NSEvent.pressedMouseButtons == 0, !movingToSpace else { return }
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
            guard let w = windows[id], let src = screen(of: w, in: screens) else { continue }
            if floatsFreely(id) {
                // Otherwise the next workspace switch parks it back on the display it came from.
                if let dst = screen(containing: w.frame, in: screens), dst.uuid != src.uuid, let ws = shown[dst.uuid] { workspaceOf[id] = ws }
                continue
            }
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
        guard !f.isNull else { return } // unknown geometry: a null rect's infinite origin would set the ratio to an extreme
        let mains = [.bsp, .twoPane, .twoPaneRight].contains(st.layout) ? 1 : st.mainCount
        guard let idx = ids.firstIndex(of: w.id), ids.count > mains, var axis = st.layout.ratioAxis else { return }
        if st.layout == .bsp { axis = (r.width >= r.height, true) }
        let isMain = idx < mains
        if st.layout == .widescreenTall, isMain, mains > 1, idx != mains - 1 { return }
        if st.layout == .widescreenTallRight, isMain, mains > 1, idx != 0 { return }
        if !isMain, [.threeColumnLeft, .threeColumnRight].contains(st.layout) { return }
        let gap = config.windowMargins ? config.windowMarginSize : 0
        let total = axis.horizontal ? r.width : r.height
        // Distance of the main/secondary edge from the main pane's outer side, as `f` puts it.
        func boundary(_ f: CGRect) -> CGFloat {
            switch (axis.horizontal, axis.fromStart, isMain) {
            case (true, true, true): f.maxX - r.minX + gap
            case (true, true, false): f.minX - r.minX
            case (true, false, true): r.maxX - f.minX + gap
            case (true, false, false): r.maxX - f.maxX
            case (false, _, true): f.maxY - r.minY + gap
            case (false, _, false): f.minY - r.minY
            }
        }
        // Only a window whose slot sits on the split can move it (not e.g. a deeper BSP tile).
        if let (slots, _) = rawSlots(ids, on: s, st, ratio: st.ratio), slots.indices.contains(idx),
           abs(boundary(slots[idx]) - st.ratio * (total + gap)) > 3 { return }
        st.ratio = min(0.9, max(0.1, boundary(f) / (total + gap)))
    }

    // MARK: - Status & IPC

    struct Status {
        var trusted: Bool
        var keybindsActive: Bool
        var running: Bool
        var tilingEnabled: Bool
        var launchAtLogin: Bool
        var loginNeedsApproval: Bool
        var inputMonitoring: Bool
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
                      inputMonitoring: Permissions.inputMonitoringGranted,
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
        if config.enablesLayoutHUD { HUD.shared.show(l.title, layout: l, on: s.ns) }
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
            // Diagnostics: `ouch poststyle 0|1|2` picks how synthetic shortcuts are sent.
            if let n = Int(parts[1]), let style = Hotkeys.PostStyle(rawValue: n) { Hotkeys.postStyle = style }
            Log.info("ipc: post style is now \(Hotkeys.postStyle)")
        case "reload": reload()
        case "modefx": ModeFX.shared.command(Array(parts.dropFirst()).flatMap { $0.split(separator: " ").map(String.init) })
        case "panelfx": PanelMotionDemo.command(Array(parts.dropFirst()))
        case "introlab": IntroLab.shared.open()
        case "intro": Onboarding.shared.playIntro(parts.dropFirst().first.flatMap { IntroScore.Arrangement.named($0) } ?? .standard)
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
        let inMode = !Hotkeys.shared.submap.isEmpty
        defer { onDispatch?(dispatcher, arg, inMode) }
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
        case "toggledim": FocusDim.shared.toggleDim()
        case "toggleblur": FocusDim.shared.toggleBlur()
        case "submap": Hotkeys.shared.setSubmap(arg)
        case "sethomespace": makeCurrentSpaceHome()
        case "sort":
            if config.virtualWorkspaces { SortPanel.shared.toggle() }
            else { HUD.shared.show("Sorting needs Ouch workspaces", on: currentScreen()?.ns) }
        case "sort-undo": SortPanel.shared.undoApplied()
        case "retile", "reevaluate": corrections = [:]; refresh()
        case "reload": reload()
        case "exit": NSApp.terminate(nil)
        default: NSLog("Ouch: unknown dispatcher %@", dispatcher)
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
        default: NSLog("Ouch: unknown layoutmsg %@", cmd)
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
        let candidates = order.filter(visible.contains).compactMap { windows[$0] } // tiling order breaks ties
        let screens = Screen.all()
        let home = screen(of: w, in: screens)
        // A zoomed window covers everything else: there's no geometry to navigate, so cycle.
        if let home, state(for: home).zoomed == w.id { cycleFocus(d == .left || d == .up ? -1 : 1); return }
        if let n = neighbor(of: w, d, among: candidates) { focus(n); return }
        let f = navFrame(w)
        let here = candidates.filter { $0.id != w.id && screen(of: $0, in: screens)?.uuid == home?.uuid }
        // At the end of a row or column: wrap round to the far end of it.
        let behind = here.compactMap { o -> (Window, CGFloat)? in
            let r = relation(f, navFrame(o), d)
            return r.overlaps && r.along < -1 ? (o, -r.along) : nil
        }
        if let far = behind.map(\.1).max() {
            let ends = behind.filter { $0.1 >= far - 2 }.map(\.0)
            if let pick = ends.max(by: { (focusStamps[$0.id] ?? 0) < (focusStamps[$1.id] ?? 0) }) { focus(pick) }
            return
        }
        // Windows stacked in the same slot (fullscreen layout, a two-pane stack): cycle through them.
        let hereIDs = Set(here.map(\.id))
        let stack = candidates.filter { $0.id == w.id || (hereIDs.contains($0.id) && navFrame($0).approxEqual(f, tolerance: 2)) }
        guard stack.count > 1, let i = stack.firstIndex(where: { $0.id == w.id }) else { return }
        let delta = d == .left || d == .up ? -1 : 1
        focus(stack[((i + delta) % stack.count + stack.count) % stack.count])
    }

    private func moveWindow(_ d: Direction) {
        guard let w = focusedWindow(), !w.isFloating else { return }
        let candidates = order.filter(visible.contains).compactMap { windows[$0] }.filter { !$0.isFloating }
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
        var ratio = c.st.ratio
        if parts.first == "exact", parts.count > 1, let v = Double(parts[1]) {
            ratio = CGFloat(v)
        } else {
            let delta = Double(arg.replacingOccurrences(of: "+", with: "")).map { CGFloat($0) } ?? config.windowResizeStep
            ratio += delta
        }
        ratio = min(0.9, max(0.1, ratio))
        // A window we already know won't shrink: say so and keep the ratio, so the presses that
        // did nothing don't have to be undone before the other direction works again.
        if let stubborn = windowRefusingRatio(ratio, from: c.st.ratio, ids: c.ids, on: c.s, c.st) {
            warnTooSmall(stubborn, on: c.s)
            return
        }
        c.st.ratio = ratio
        // Otherwise a window may only turn out to have a minimum once it's been asked to shrink.
        ratioChange = (c.s.uuid, Date() + (config.animate ? config.animationDuration : 0) + 0.6)
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
        let i = config.layouts.firstIndex(of: c.st.layout) ?? (delta > 0 ? -1 : 0)
        setLayout(config.layouts[((i + delta) % config.layouts.count + config.layouts.count) % config.layouts.count])
    }

    private func setLayout(_ l: Layout) {
        guard let c = context() else { return }
        c.st.layout = l
        c.st.zoomed = nil
        corrections = [:]
        refresh()
        if config.enablesLayoutHUD { HUD.shared.show(l.title, layout: l, on: c.s.ns) }
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
            CursorRefresh.soon()
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
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
            workspaceOf[w.id] = shown[dst.uuid]
            scheduleRefresh()
        } else {
            workspaceOf[w.id] = shown[dst.uuid]
            refresh()
        }
        focus(w)
    }

    // MARK: - Ouch workspaces

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
        for (id, ws) in workspaceOf where windows[id] != nil && isVirtual(ws) && !isPending(ws) { counts[ws, default: 0] += 1 }
        let names = Set(counts.keys).union(virtualShown.values).sorted(by: workspaceSort)
        let showing = Set(virtualShown.values)
        let current = currentScreen().flatMap { virtualShown[$0.uuid] }
        return (current, names.map { ($0, counts[$0] ?? 0, showing.contains($0)) })
    }

    /// What the menu bar shows for the focused display: its workspace (or macOS desktop number),
    /// layout, and the apps on it in tiling order (floating ones last).
    func menuBarState() -> (workspace: String?, layout: Layout, pids: [pid_t])? {
        guard isStarted, let s = currentScreen() else { return nil }
        let ws = shown[s.uuid]
        let workspace: String?
        if config.virtualWorkspaces {
            workspace = virtualShown[s.uuid]
        } else if let list = Spaces.list(display: s.uuid), let cur = list.current, let n = list.desktops.firstIndex(of: cur) {
            workspace = String(n + 1)
        } else {
            workspace = nil
        }
        let here = order.filter { workspaceOf[$0] == ws && present.contains($0) }.compactMap { windows[$0] }
        var seen = Set<pid_t>()
        let pids = (here.filter { !$0.isFloating } + here.filter(\.isFloating)).map(\.pid).filter { seen.insert($0).inserted }
        return (workspace, state(for: s).layout, pids)
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
            let occupied = Set(workspaceOf.values).union(virtualShown.values).filter { isVirtual($0) && !isPending($0) }.sorted(by: workspaceSort)
            guard !occupied.isEmpty else { return nil }
            let i = occupied.firstIndex(of: cur) ?? 0
            return occupied[((i + d) % occupied.count + occupied.count) % occupied.count]
        }
        return a
    }

    /// Keeps workspace bookkeeping consistent with the displays that exist. In macOS-Spaces mode,
    /// mirrors whatever Space each display is showing.
    private func isVirtual(_ ws: String?) -> Bool { ws.map { !$0.hasPrefix("space:") } ?? false }

    /// While the Sort panel is open, windows put in Close wait on a workspace of their own per display, which
    /// is never shown (so the usual parking hides them), never listed and never saved.
    private static let pendingPrefix = "sort-close:"
    private func isPending(_ ws: String?) -> Bool { ws?.hasPrefix(Self.pendingPrefix) == true }

    /// Keeps workspace bookkeeping consistent with the displays that exist.
    ///
    /// Ouch workspaces live on one "home" macOS Space per display. On any other Space a
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
                    let own = monitorOf.filter { $0.value == s.uuid && isVirtual($0.key) && !isPending($0.key) && !virtualShown.values.contains($0.key) }
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
        // A window we can see but whose workspace isn't showing is either parked (a Ouch
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

    /// Makes the macOS Space each display is showing now the one Ouch workspaces live on.
    func makeCurrentSpaceHome() {
        guard config.virtualWorkspaces else { return }
        for s in Screen.all() {
            homeSpace[s.uuid] = Spaces.current(display: s.uuid)
            if !isVirtual(virtualShown[s.uuid]) { virtualShown[s.uuid] = nil }
        }
        // Windows here join the workspace that's now showing instead of a per-Space one.
        workspaceOf = workspaceOf.filter { isVirtual($0.value) }
        refresh()
        HUD.shared.show("Ouch workspaces live on this Desktop", on: currentScreen()?.ns)
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

    /// Is this display currently showing its home Space (where Ouch workspaces live)?
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
        if let slide, slide.outgoing.contains(id) {
            // Slides off the edge. `beginSlide` moves it into the corner once the slide is done.
            let s = workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { u in screens.first { $0.uuid == u } } ?? screens[0]
            let x = slide.forward ? s.frame.minX - f.width + 1 : s.frame.maxX - 1
            let edge = CGRect(x: x, y: f.minY, width: f.width, height: f.height)
            // Already at the edge, or already sliding there: nothing to do, and its floating frame is still right.
            guard !f.approxEqual(edge, tolerance: 2), !animator.isMoving(id, to: edge) else { return }
            floatFrames[id] = floatsFreely(id) ? f : nil
            animator.animate([.init(window: w, to: edge, bounds: s.visible)],
                             duration: config.animationDuration, curve: config.animationCurve, bounce: config.animationBounce)
            return
        }
        floatFrames[id] = floatsFreely(id) ? f : nil
        cornerPark(id, screens: screens)
    }

    /// Moves a window into the parking corner of its display. Keeps `floatFrames` as it is.
    private func cornerPark(_ id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id] else { return }
        let s = workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { u in screens.first { $0.uuid == u } } ?? screens[0]
        animator.cancel(id)
        animator.quiet(id)
        EnhancedUI.suspend(w.pid)
        w.setPosition(parkingSpot(size: w.frame.size, on: s, screens))
        EnhancedUI.resume(w.pid)
    }

    /// Windows nothing lays out: floating ones, everything on a Floating-layout workspace, and all
    /// windows while tiling is off. Parking keeps their frame and showing their workspace puts it back.
    private func floatsFreely(_ id: CGWindowID) -> Bool {
        guard let w = windows[id] else { return false }
        if w.isFloating || !tilingEnabled { return true }
        guard let ws = workspaceOf[id] else { return false }
        return (states[ws]?.layout ?? config.layouts.first) == .floating
    }

    private func unpark(floating id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id] else { return }
        let f = w.frame
        guard isParked(f, screens) else { floatFrames[id] = nil; return }
        let s = screen(of: w, in: screens) ?? screens[0]
        var r = floatFrames.removeValue(forKey: id) ?? targets[id]
            ?? CGRect(x: s.visible.midX - f.width / 2, y: s.visible.midY - f.height / 2, width: f.width, height: f.height)
        r.origin.x = max(s.visible.minX, min(r.origin.x, s.visible.maxX - r.width))
        r.origin.y = max(s.visible.minY, min(r.origin.y, s.visible.maxY - r.height))
        animator.quiet(id)
        if let from = slideStart(id, to: r, on: s) {
            animator.animate([.init(window: w, to: r, bounds: s.visible, from: from)],
                             duration: config.animationDuration, curve: config.animationCurve, bounce: config.animationBounce)
            return
        }
        EnhancedUI.suspend(w.pid)
        w.setFrame(r)
        EnhancedUI.resume(w.pid)
    }

    /// A workspace swap on this display. The windows leaving slide off the edge, then park in a corner.
    /// The windows arriving slide in from the other edge. Both use the window animation settings.
    /// Skipped when animations are off, or when too many windows would move (like a big relayout).
    private func beginSlide(from previous: String, to ws: String, on s: Screen) {
        // A swap still running: its leaving windows go to their corner now, so this swap starts from there.
        if let old = slide { for id in old.outgoing where !visible.contains(id) { cornerPark(id, screens: Screen.all()) } }
        slide = nil
        guard config.animate, config.animationDuration >= 0.01 else { return }
        let outgoing = visible.filter { workspaceOf[$0] == previous }
        let arriving = present.filter { workspaceOf[$0] == ws }
        guard outgoing.count + arriving.count <= Self.maxAnimatedMoves else { return }
        let until = CACurrentMediaTime() + config.animationDuration
        slide = Slide(monitor: s.uuid, to: ws, outgoing: outgoing, forward: workspaceSort(previous, ws), until: until)
        // Wait past the animator's landing check (`verify`) before the corner park, or it would move the window back.
        DispatchQueue.main.asyncAfter(deadline: .now() + config.animationDuration + 0.2) { [weak self] in
            guard let self, self.slide?.until == until else { return }
            let screens = Screen.all()
            for id in outgoing where !self.visible.contains(id) { self.cornerPark(id, screens: screens) }
            self.slide = nil
        }
    }

    /// Where a window arriving in a workspace swap starts its slide, or nil when it does not slide.
    private func slideStart(_ id: CGWindowID, to target: CGRect, on s: Screen) -> CGRect? {
        guard let slide, slide.monitor == s.uuid, slide.to == workspaceOf[id], CACurrentMediaTime() < slide.until else { return nil }
        let x = slide.forward ? s.frame.maxX - 1 : s.frame.minX - target.width + 1
        return CGRect(x: x, y: target.minY, width: target.width, height: target.height)
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
        labels = d.dictionary(forKey: "ws.labels") as? [String: String] ?? [:]
        virtualShown = d.dictionary(forKey: "ws.shown") as? [String: String] ?? [:]
        for (k, v) in d.dictionary(forKey: "ws.home") as? [String: NSNumber] ?? [:] { homeSpace[k] = v.uint64Value }
        for (k, v) in d.dictionary(forKey: "ws.floating") as? [String: Bool] ?? [:] {
            if let id = CGWindowID(k) { savedFloating[id] = v }
        }
        // "layout ratio mainCount" per workspace, so a restart (or an update) keeps each one's arrangement.
        for (ws, v) in d.dictionary(forKey: "ws.layouts") as? [String: String] ?? [:] where isVirtual(ws) {
            let parts = v.split(separator: " ").map(String.init)
            guard let layout = parts.first.flatMap(Layout.init(rawValue:)) else { continue }
            let st = state(workspace: ws)
            st.layout = layout
            if parts.count > 1, let r = Double(parts[1]) { st.ratio = min(0.9, max(0.1, CGFloat(r))) }
            if parts.count > 2, let m = Int(parts[2]) { st.mainCount = max(1, min(10, m)) }
        }
        monitorOf = monitorOf.filter { isVirtual($0.key) }
    }

    private func owner(_ w: Window) -> String { "\(w.pid) \(w.bundleID ?? "")" }

    private func saveWorkspaces() {
        guard config.virtualWorkspaces else { return }
        let windowsMap = Dictionary(workspaceOf.filter { windows[$0.key] != nil && isVirtual($0.value) && !isPending($0.value) }.map { (String($0.key), $0.value) },
                                    uniquingKeysWith: { a, _ in a })
        let monitors = monitorOf.filter { isVirtual($0.key) && !isPending($0.key) }
        let floating = Dictionary(windowsMap.keys.compactMap { k in CGWindowID(k).flatMap { windows[$0]?.userFloating }.map { (k, $0) } },
                                  uniquingKeysWith: { a, _ in a })
        let layouts = Dictionary(states.filter { isVirtual($0.key) && !isPending($0.key) }
                                    .map { ($0.key, "\($0.value.layout.rawValue) \($0.value.ratio) \($0.value.mainCount)") },
                                 uniquingKeysWith: { a, _ in a })
        let key = "\(windowsMap.sorted { $0.key < $1.key })|\(monitors.sorted { $0.key < $1.key })|\(virtualShown.sorted { $0.key < $1.key })|\(homeSpace.sorted { $0.key < $1.key })|\(labels.sorted { $0.key < $1.key })|\(floating.sorted { $0.key < $1.key })|\(layouts.sorted { $0.key < $1.key })"
        guard key != lastSavedWorkspaces else { return }
        lastSavedWorkspaces = key
        let d = UserDefaults.standard
        d.set(windowsMap, forKey: "ws.windows")
        d.set(Dictionary(windowsMap.keys.compactMap { k in CGWindowID(k).flatMap { windows[$0] }.map { (k, owner($0)) } },
                         uniquingKeysWith: { a, _ in a }), forKey: "ws.owners")
        d.set(monitors, forKey: "ws.monitors")
        d.set(virtualShown, forKey: "ws.shown")
        d.set(homeSpace.mapValues { NSNumber(value: $0) }, forKey: "ws.home")
        d.set(labels, forKey: "ws.labels")
        d.set(floating, forKey: "ws.floating")
        d.set(layouts, forKey: "ws.layouts")
    }

    /// Hyprland's `workspace`: shows it on its display (a new one opens on the focused display)
    /// and focuses the window you last used there.
    func showWorkspace(_ ws: String, focusing preferred: Window? = nil, focus takesFocus: Bool = true, attempts: Int = 3) {
        let screens = Screen.all()
        guard let here = currentScreen() ?? screens.first else { return }
        let monitor = monitorOf[ws].flatMap { u in screens.first { $0.uuid == u } } ?? here
        let leaving = virtualShown[monitor.uuid]
        if let cur = leaving, cur != ws { previousWorkspace[monitor.uuid] = cur }
        monitorOf[ws] = monitor.uuid
        virtualShown[monitor.uuid] = ws
        autoSwitchAfter = Date().addingTimeInterval(0.6)
        // Away from the home Space, a workspace can't be shown without going there; a quiet show just records it.
        if !takesFocus, !isOnHomeSpace(monitor) { return }
        // On another macOS Space? Go to the home Space first, then show the workspace there.
        if !isOnHomeSpace(monitor), let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
           let index = info.ids.firstIndex(of: home), let desktop = info.desktops.firstIndex(of: index) {
            guard attempts > 0 else { Log.info("workspaces: couldn't reach the home Space for \(ws)"); return }
            stageHomeSpace(ws, replacing: leaving, on: monitor, home: home)
            CGWarpMouseCursorPosition(monitor.center) // space switching acts on the display under the pointer
            guard let steps = goToSpace(desktop + 1) else { Log.info("workspaces: can't switch Spaces for \(ws)"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.15 * Double(steps)) { [weak self] in
                self?.showWorkspace(ws, focusing: preferred, attempts: attempts - 1)
            }
            return
        }
        let previous = shown[monitor.uuid]
        let changed = previous != ws
        shown[monitor.uuid] = ws
        Log.debug("workspaces: showing \(ws) on \(monitor.ns.localizedName)")
        // Quiet shows (a sort, restoring a layout) snap; a switch the user asked for slides.
        if changed, takesFocus, let previous { beginSlide(from: previous, to: ws, on: monitor) }
        refresh()
        if changed, !quietWorkspaceHUD, config.enablesLayoutHUD, config.enablesLayoutHUDOnSpaceChange {
            HUD.shared.show(labels[ws].map { "\(ws) · \($0)" } ?? ws, layout: state(workspace: ws).layout, on: monitor.ns)
        }
        guard takesFocus else {
            onChange?()
            return
        }
        let candidates = [preferred?.id, lastFocused[ws]].compactMap { $0 } + order + Array(visible)
        if let id = candidates.first(where: { visible.contains($0) && workspaceOf[$0] == ws }), let w = windows[id] {
            focus(w)
        } else {
            parkFocus()
            if config.mouseFollowsFocus { CGWarpMouseCursorPosition(monitor.center) }
            CursorRefresh.soon()
        }
        onChange?()
    }

    /// Before going back to the home Space from another macOS Space, sets the home Space up to show `ws`
    /// while it is still out of sight: the workspace that was showing there parks, and `ws` takes its tiles.
    /// Otherwise the Space slide shows the old workspace first, and only then swaps to `ws`.
    private func stageHomeSpace(_ ws: String, replacing old: String?, on s: Screen, home: UInt64) {
        guard config.virtualWorkspaces, isVirtual(ws) else { return }
        let screens = Screen.all()
        func onHome(_ id: CGWindowID) -> Bool { Spaces.of(window: id).contains(home) }
        if let old, old != ws, isVirtual(old) {
            for id in order where workspaceOf[id] == old && onHome(id) { park(id, screens: screens) }
        }
        // The windows a refresh would find there: not minimized, and their app not hidden.
        let arriving = order.filter { id in
            guard workspaceOf[id] == ws, let w = windows[id], !w.isNativeFullscreen, onHome(id),
                  w.element.bool(kAXMinimizedAttribute) != true,
                  NSRunningApplication(processIdentifier: w.pid)?.isHidden != true else { return false }
            return true
        }
        for id in arriving where floatsFreely(id) { unpark(floating: id, screens: screens) }
        let ids = arriving.filter { windows[$0]?.isFloating == false }
        let st = state(workspace: ws)
        guard tilingEnabled, !ids.isEmpty, let (raw, gap) = rawSlots(ids, on: s, st, ratio: st.ratio) else { return }
        let slots = fitMinimums(raw, mins: ids.map { minSizes[$0] }, gap: gap)
        var moves: [Animator.Move] = []
        for (id, slot) in zip(ids, slots) {
            guard let w = windows[id] else { continue }
            let target = id == st.zoomed ? usableRect(s).pixelAligned : slot
            targets[id] = target
            if !w.frame.approxEqual(target) { moves.append(.init(window: w, to: target, bounds: s.visible)) }
        }
        animator.animate(moves, duration: 0)
        Log.debug("workspaces: staged \(ws) on the home Space (\(arriving.count) windows, parked \(old ?? "none"))")
    }

    /// Hyprland's `movetoworkspace` (follow) and `movetoworkspacesilent`.
    private func moveFocusedWindow(to ws: String, follow: Bool) {
        guard let w = focusedWindow(), workspaceOf[w.id] != ws else { return }
        moveWindow(w, toWorkspace: ws, follow: follow)
    }

    /// Move the real window first; only commit Ouch's assignment after WindowServer confirms it.
    private func moveWindow(_ w: Window, toWorkspace ws: String, follow: Bool) {
        let screens = Screen.all()
        guard config.virtualWorkspaces, isVirtual(ws), !workspaceMoves.contains(w.id),
              let monitor = monitorOf[ws].flatMap({ uuid in screens.first { $0.uuid == uuid } })
                ?? currentScreen() ?? screens.first,
              let home = homeSpace[monitor.uuid], let info = Spaces.list(display: monitor.uuid),
              info.desktops.contains(where: { info.ids[$0] == home }), !w.isNativeFullscreen else { return }
        if Spaces.of(window: w.id) == [home] {
            assignWindow(w, toWorkspace: ws, from: workspaceOf[w.id], display: monitor.uuid, follow: follow)
            return
        }
        let known = windows[w.id] != nil, from = workspaceOf[w.id], frame = w.frame
        workspaceMoves.insert(w.id)
        autoSwitchAfter = Date().addingTimeInterval(0.7)
        // Put the window in its tile while it is still on its old Desktop, out of sight. It then
        // arrives in its tile, instead of at its old frame on top of the other tiles. The other
        // tiles keep their frames for now, and make room with the usual animation once it is here.
        if !known { windows[w.id] = w; order.append(w.id) }
        workspaceOf[w.id] = ws
        monitorOf[ws] = monitor.uuid
        snapNextPlacement.insert(w.id)
        refresh(instant: true, placing: [w.id])
        animator.afterPendingWrites { [weak self] in
            // Hold the display through the Space move only, so the animation after it is not frozen.
            let displayBatch = WindowServerUpdates.shared.begin()
            let moveStarted = Date()
            func release() {
                let held = Int(Date().timeIntervalSince(moveStarted) * 1000)
                let watchdog = Int(WindowServerUpdates.shared.maximumHold * 1000)
                Log.info("workspaces: import of \(w.id) held the display \(held) ms\(held > watchdog ? " (watchdog let go at \(watchdog) ms)" : "")")
                displayBatch?.finish()
            }
            Spaces.move(window: w.id, to: home, waitUntilOnScreen: self?.isOnHomeSpace(monitor) ?? false) { [weak self] moved in
                guard let self else { release(); return }
                workspaceMoves.remove(w.id)
                guard moved, w.isValid, config.virtualWorkspaces, homeSpace[monitor.uuid] == home else {
                    Log.info("workspaces: direct move of \(w.id) to \(home) failed")
                    HUD.shared.show("macOS couldn't move this window", on: monitor.ns)
                    if known { workspaceOf[w.id] = from } else { forget(w.id) }
                    if w.isValid, !frame.isNull { w.setFrame(frame) }
                    refresh()
                    release()
                    return
                }
                Log.info("workspaces: moved \(w.id) to home Desktop in \(Int(Date().timeIntervalSince(moveStarted) * 1000)) ms")
                if !known { watch(w) }
                release()
                assignWindow(w, toWorkspace: ws, from: from, display: monitor.uuid, follow: follow)
            }
        }
    }

    private func assignWindow(_ w: Window, toWorkspace ws: String, from: String?, display: String, follow: Bool) {
        if windows[w.id] == nil {
            windows[w.id] = w
            order.append(w.id)
            watch(w)
        }
        monitorOf[ws] = display
        workspaceOf[w.id] = ws
        lastFocused[ws] = w.id
        if let from, lastFocused[from] == w.id { lastFocused[from] = nil }
        corrections[w.id] = nil
        if follow {
            showWorkspace(ws, focusing: w)
        } else {
            autoSwitchAfter = Date().addingTimeInterval(0.6)
            refresh()
            guard isShown(from) else { return } // importing a background window keeps the current focus
            if let next = order.first(where: { workspaceOf[$0] == from && visible.contains($0) }).flatMap({ windows[$0] }) {
                focus(next)
            } else {
                parkFocus()
            }
        }
    }

    /// Menu candidates from every Desktop. Discovery never activates the app or raises its windows.
    /// The window server names the candidate windows first, so only their apps get AX queries.
    /// An overall deadline keeps one slow app from stalling the menu.
    func windowsOnOtherDesktops() -> [Window] {
        guard config.virtualWorkspaces, isStarted, Spaces.canMoveWindows,
              let s = currentScreen(), isOnHomeSpace(s) else { return [] }
        let deadline = Date().addingTimeInterval(0.3)
        let screens = Screen.all()
        let desktops = Set(screens.flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        let homes = Set(homeSpace.values)
        // Windows on another Desktop are off screen; the window list still has them with their pid.
        var offDesktop: [pid_t: Set<CGWindowID>] = [:]
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in list where (d[kCGWindowLayer as String] as? Int) == 0 && (d[kCGWindowIsOnscreen as String] as? Bool) != true {
            guard let n = d[kCGWindowNumber as String] as? Int, let pid = d[kCGWindowOwnerPID as String] as? Int,
                  !workspaceMoves.contains(CGWindowID(n)) else { continue }
            let membership = Spaces.of(window: CGWindowID(n))
            guard membership.count == 1, let space = membership.first, desktops.contains(space), !homes.contains(space) else { continue }
            offDesktop[pid_t(pid), default: []].insert(CGWindowID(n))
        }
        var result: [Window] = []
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != getpid() {
            guard let ids = offDesktop[app.processIdentifier] else { continue }
            guard Date() < deadline else { break }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.1)
            // Some apps omit inactive-Desktop windows from AXWindows. Keep using the AX
            // handles Ouch discovered earlier while those Desktops were visible.
            let known = windows.values.filter { $0.pid == app.processIdentifier && ids.contains($0.id) }.map(\.element)
            let candidates = (known.count < ids.count ? element.elements(kAXWindowsAttribute) : []) + known
            var seen: Set<CGWindowID> = []
            for el in candidates {
                guard Date() < deadline else { break }
                AXUIElementSetMessagingTimeout(el, 0.1)
                guard let id = el.windowID, ids.contains(id), seen.insert(id).inserted,
                      el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole,
                      el.bool(kAXMinimizedAttribute) != true, el.bool("AXFullScreen") != true else { continue }
                let w = windows[id] ?? Window(id: id, element: el, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
                if w.naturalFrame.isNull { w.naturalFrame = w.frame; w.autoFloating = shouldFloat(w) }
                result.append(w)
            }
        }
        return result.sorted { ($0.bundleID ?? "", $0.id) < ($1.bundleID ?? "", $1.id) }
    }

    /// Pull an inactive Desktop's window into the workspace showing here, keeping this Desktop active.
    func bringWindowHere(_ w: Window) {
        guard let s = currentScreen(), isOnHomeSpace(s), let ws = virtualShown[s.uuid] else { return }
        moveWindow(w, toWorkspace: ws, follow: false)
    }

    /// Capture the destination before the Dock gets a chance to activate another Desktop.
    /// Only intercept an app's ordinary click when its preferred window is on a native Desktop.
    private func prepareDockPull(at point: CGPoint) -> (() -> Void)? {
        let deadline = Date().addingTimeInterval(0.15)
        // Most clicks are nowhere near the Dock: let them through before any screen, Space or AX query.
        guard isStarted, config.virtualWorkspaces, !sortSession, dockArea.contains(point), Spaces.canMoveWindows,
              let display = Screen.all().first(where: { $0.frame.contains(point) }),
              isOnHomeSpace(display), let ws = virtualShown[display.uuid],
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(dockElement, 0.03)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockElement, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.03)
        guard hit.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = hit.value(kAXURLAttribute) as? URL,
              let app = NSWorkspace.shared.runningApplications.first(where: {
                  $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
              }), app.processIdentifier != getpid(), !app.isHidden else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.03)
        // The focused/main window wins over other windows of the same app, just like the Dock.
        let candidates = [appElement.element(kAXFocusedWindowAttribute), appElement.element(kAXMainWindowAttribute)].compactMap { $0 }
            + focusOrder.compactMap { windows[$0] }.filter { $0.pid == app.processIdentifier }.map(\.element)
            + appElement.elements(kAXWindowsAttribute)
        let desktops = Set(Screen.all().flatMap { screen -> [UInt64] in
            guard let info = Spaces.list(display: screen.uuid) else { return [] }
            return info.desktops.map { info.ids[$0] }
        })
        var seen: Set<CGWindowID> = []
        for el in candidates {
            guard Date() < deadline else { return nil } // never stall the mouse tap on an unresponsive app
            AXUIElementSetMessagingTimeout(el, 0.03)
            guard let id = el.windowID, seen.insert(id).inserted else { continue }
            guard el.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { continue }
            // If the window the Dock would select is already on an Ouch home Desktop,
            // minimized, sticky, or fullscreen, let the Dock handle it normally.
            let membership = Spaces.of(window: id)
            guard membership.count == 1, let source = membership.first,
                  desktops.contains(source), !homeSpace.values.contains(source),
                  !workspaceMoves.contains(id), el.bool(kAXMinimizedAttribute) != true,
                  el.bool("AXFullScreen") != true else { return nil }
            let w = windows[id] ?? Window(id: id, element: el, pid: app.processIdentifier, bundleID: app.bundleIdentifier)
            return { [weak self] in
                guard let self, config.virtualWorkspaces, virtualShown[display.uuid] == ws,
                      isOnHomeSpace(display), w.isValid else { return }
                if w.naturalFrame.isNull { w.naturalFrame = w.frame; w.autoFloating = shouldFloat(w) }
                pendingFocus = nil
                Hotkeys.shared.setSubmap("")
                moveWindow(w, toWorkspace: ws, follow: true)
            }
        }
        return nil
    }

    /// If the focused window lives on a hidden workspace (⌘-Tab, Dock, a link opening a window),
    /// switch to it. Also remembers each workspace's last focused window.
    private func followFocus() {
        guard isStarted, let w = reportedFocusedWindow() else { return }
        if let p = pendingFocus {
            // Until macOS catches up with a focus we asked for, its reports are stale.
            guard p.id == w.id else { return }
            pendingFocus = nil
        }
        if focusStamps[w.id] != focusClock { noteFocus(w.id) }
        focusOrder.removeAll { $0 == w.id }
        focusOrder.insert(w.id, at: 0)
        if focusOrder.count > 80 { focusOrder.removeLast(focusOrder.count - 80) }
        guard !sortSession else { return }
        guard config.virtualWorkspaces, let ws = workspaceOf[w.id], isVirtual(ws) else { return }
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

    // MARK: - Sort

    /// Everything a sort can change, as it was when the panel opened, for Revert and the toast's Undo.
    private struct SortSnapshot {
        var workspaceOf: [CGWindowID: String]
        var order: [CGWindowID]
        var monitorOf: [String: String]
        var labels: [String: String]
        var layouts: [String: (layout: Layout, ratio: CGFloat, mainCount: Int)]
        var shown: [String: String]
        var focused: CGWindowID?
    }

    /// The toast went away: the last sort can no longer be undone.
    func dropSortSnapshot() { sortSnapshot = nil }

    /// Every display with its tiled windows and workspaces, left to right, for the Sort panel.
    func sortDisplays() -> [SortDisplay] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        guard let first = screens.first else { return [] }
        var rank: [CGWindowID: Int] = [:]
        for (i, id) in ([focusedWindow()?.id].compactMap { $0 } + focusOrder).enumerated() where rank[id] == nil { rank[id] = i }
        for (i, info) in CGWindowInfo.onScreen().enumerated() where rank[info.id] == nil { rank[info.id] = 1000 + i }
        func home(_ id: CGWindowID) -> String { workspaceOf[id].flatMap { monitorOf[$0] } ?? first.uuid }
        let tiledIDs = order.filter { present.contains($0) && windows[$0]?.isFloating == false && isVirtual(workspaceOf[$0]) && !isPending(workspaceOf[$0]) }
        let names = screens.map(Self.shortName)
        var shorts = names
        for (i, name) in names.enumerated() where names.filter({ $0 == name }).count > 1 {
            shorts[i] = "\(name) \(names[..<i].filter { $0 == name }.count + 1)"
        }
        return screens.enumerated().map { n, s in
            let mine = tiledIDs.filter { home($0) == s.uuid }
            let items = mine.compactMap { id -> SortItem? in
                guard let w = windows[id] else { return nil }
                let app = NSRunningApplication(processIdentifier: w.pid)
                let title = w.element.string(kAXTitleAttribute) ?? ""
                return SortItem(id: id, title: title.isEmpty ? "Untitled" : title, app: app?.localizedName ?? w.bundleID ?? "App",
                                bundleID: w.bundleID, icon: app?.icon, recency: rank[id] ?? 2000)
            }
            let active = virtualShown[s.uuid]
            var names = Set(mine.compactMap { workspaceOf[$0] })
            if let active { names.insert(active) }
            let spaces = names.sorted(by: workspaceSort).map { name in
                SortWorkspace(name: name, label: labels[name] ?? "", layout: states[name]?.layout ?? config.layouts.first ?? .tall,
                              ratio: states[name]?.ratio ?? 0.5, mainCount: states[name]?.mainCount ?? 1,
                              ids: mine.filter { workspaceOf[$0] == name })
            }
            let taken = Set(monitorOf.filter { $0.value != s.uuid && isVirtual($0.key) && !isPending($0.key) }.keys)
                .union(virtualShown.filter { $0.key != s.uuid }.values)
                .union(tiledIDs.filter { home($0) != s.uuid }.compactMap { workspaceOf[$0] })
            return SortDisplay(id: s.uuid, name: s.ns.localizedName, short: shorts[n], isLaptop: s.isBuiltin,
                               aspect: s.frame.width / max(s.frame.height, 1), screen: s.ns, items: items, workspaces: spaces,
                               active: active, taken: taken)
        }
    }

    private static func shortName(_ s: Screen) -> String {
        if s.isBuiltin { return "Built-in" }
        let words = s.ns.localizedName.split(separator: " ").filter { $0.lowercased() != "display" }
        return words.isEmpty ? s.ns.localizedName : words.joined(separator: " ")
    }

    /// The panel opened: remember how everything is now (for Revert and Undo), and from here on keep
    /// focus and workspace switching out of the way until `finishSort`, `revertSort` or `endSort`.
    func beginSort() {
        var layouts: [String: (layout: Layout, ratio: CGFloat, mainCount: Int)] = [:]
        for (name, st) in states { layouts[name] = (st.layout, st.ratio, st.mainCount) }
        sortSnapshot = SortSnapshot(workspaceOf: workspaceOf, order: order, monitorOf: monitorOf, labels: labels, layouts: layouts,
                                    shown: virtualShown, focused: focusedWindow()?.id)
        sortSession = true
    }

    /// Windows that still exist, so the panel can drop rows for ones that closed.
    func liveWindowIDs() -> Set<CGWindowID> { Set(windows.keys) }

    /// Applies edited plans to the real windows right away: workspaces, order, layouts and names. Nothing
    /// takes focus, no workspace is switched (unless the one a display shows went away, then its first
    /// one with windows is shown) and windows in Close are hidden.
    func liveSort(_ plans: [SortApply]) {
        guard config.virtualWorkspaces, isStarted, sortSession else { return }
        let planned = plans.flatMap { $0.lanes.flatMap(\.ids) }.filter { windows[$0] != nil }
        let moving = Set(planned)
        let kept = Set(plans.flatMap { $0.lanes.map(\.name) })
        // Workspaces a plan let go of. One another display has taken over since is not ours to clear.
        var gone: [String: Set<String>] = [:]
        for p in plans {
            gone[p.display] = Set(p.dropped.filter { !kept.contains($0) && (monitorOf[$0] == nil || monitorOf[$0] == p.display) })
        }
        // The workspace each display shows afterwards, and what to do with windows outside the plan (floating,
        // hidden apps, opened while the panel was up) that sat on a workspace that goes away.
        var landing: [String: String] = [:]
        for p in plans {
            let names = Set(p.lanes.map(\.name))
            let land = virtualShown[p.display].flatMap { names.contains($0) ? $0 : nil }
                ?? (p.lanes.first { lane in lane.ids.contains { windows[$0] != nil } } ?? p.lanes.first)?.name
            guard let land else { continue }
            landing[p.display] = land
            let dropped = gone[p.display] ?? []
            for (id, ws) in workspaceOf where dropped.contains(ws) && !moving.contains(id) { workspaceOf[id] = land }
        }
        for p in plans {
            for lane in p.lanes {
                monitorOf[lane.name] = p.display
                labels[lane.name] = lane.label.isEmpty ? nil : lane.label
                let st = state(workspace: lane.name)
                st.layout = lane.layout
                st.zoomed = nil
                for id in lane.ids where windows[id] != nil { workspaceOf[id] = lane.name }
            }
            for name in gone[p.display] ?? [] { labels[name] = nil }
            // Windows in Close disappear from the screen right away; the usual parking hides them.
            let hidden = Self.pendingPrefix + p.display
            monitorOf[hidden] = p.display
            for id in p.close where windows[id] != nil { workspaceOf[id] = hidden }
        }
        order = order.filter { !moving.contains($0) } + planned
        lastFocused = lastFocused.filter { !moving.contains($0.value) }
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (display, ws) in landing where virtualShown[display] != ws { showWorkspace(ws, focus: false) }
        refresh()
    }

    /// The panel is done and the changes stay. Windows in `ids` are closed while still hidden; one that
    /// stays open (a save sheet) is then brought onto its display's shown workspace and tried again. `goTo`
    /// shows that workspace and focuses its main window; `focus` goes back to the window that had focus
    /// when the panel opened.
    func finishSort(closing ids: [CGWindowID], goTo: String?, focus: Bool) {
        sortSession = false
        guard config.virtualWorkspaces, isStarted else { return releasePending() }
        let closing = ids.filter { windows[$0] != nil }
        Log.info("sort: finishing, \(ids.count) window(s) marked to close (\(closing.count) still known), goTo=\(goTo ?? "-") focus=\(focus)")
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        if let ws = goTo {
            let main = order.first { workspaceOf[$0] == ws && present.contains($0) && !closing.contains($0) && windows[$0]?.isFloating == false }
            showWorkspace(ws, focusing: main.flatMap { windows[$0] })
        } else if focus {
            let candidates = [sortSnapshot?.focused].compactMap { $0 } + order
            if let id = candidates.first(where: { visible.contains($0) && !closing.contains($0) }), let w = windows[id] { self.focus(w) }
        }
        // Marked windows stay hidden and are closed there. Only one that is still open afterwards (an app
        // asking to save) is brought onto the shown workspace, so its sheet can be answered.
        closingNow.formUnion(closing)
        closingApps.formUnion(closing.compactMap { windows[$0]?.pid })
        releasePending()
        if !closing.isEmpty { closeMarked(closing, attempt: 0) }
    }

    /// Presses the close buttons of windows marked in the Sort panel, then checks they went and tries
    /// again (with the app's Close Window menu item for a window that has focus) if some did not.
    private func closeMarked(_ ids: [CGWindowID], attempt: Int) {
        var pressed: [CGWindowID] = []
        for id in ids {
            guard let w = windows[id], w.isValid else { continue }
            let name = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "pid \(w.pid)"
            lastClose = Date()
            var outcome = w.close()
            if outcome != "pressed", attempt > 0, focusedWindow()?.id == id { outcome += w.closeFromMenu() ? ", menu Close Window chosen" : ", no menu item" }
            Log.info("sort: close \(id) \(name) frame=\(w.frame) try \(attempt + 1): \(outcome)")
            pressed.append(id)
        }
        guard !pressed.isEmpty else { return stopClosing(ids) }
        if attempt >= 2 {
            // Last soft try done. Whatever is still open ignored the close (kitty asking "really close?"):
            // force it, unless it shows a save sheet, which is left for the user to answer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                self.forceClose(pressed.filter { self.windows[$0]?.isValid == true })
                self.stopClosing(ids)
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            var left = pressed.filter { self.windows[$0]?.isValid == true }
            Log.info("sort: \(pressed.count - left.count) of \(pressed.count) closed after try \(attempt + 1)")
            // Still open without a sheet: the app asks inside the window (kitty's "really close?"), and nobody
            // can answer that while it is hidden. Force it now, so it never comes back on screen.
            let forced = self.forceClose(left.filter { self.windows[$0].map { !Self.hasSheet($0) } ?? false })
            left.removeAll { forced.contains($0) }
            if !forced.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.stopClosing(Array(forced)) }
            }
            // Still open: most likely waiting on a save sheet. Show it, then try again once it has settled.
            stopClosing(ids.filter { !forced.contains($0) })
            guard !left.isEmpty else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.closeMarked(left, attempt: attempt + 1) }
        }
    }

    /// Force quits the app of each window that is still open, unless the app has other windows (they would be
    /// lost too) or the window has a sheet up (unsaved work).
    /// Says which windows it forced.
    @discardableResult
    private func forceClose(_ ids: [CGWindowID]) -> Set<CGWindowID> {
        var forced: Set<CGWindowID> = []
        for id in ids {
            guard let w = windows[id], w.isValid else { continue }
            let hasSheet = Self.hasSheet(w)
            let others = windows.values.contains { $0.pid == w.pid && $0.id != id && $0.isValid && !ids.contains($0.id) }
            let name = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? "pid \(w.pid)"
            if hasSheet || others { Log.info("sort: not forcing \(id) \(name): \(hasSheet ? "sheet up" : "app has other windows")"); continue }
            Log.info("sort: force quitting \(name) for window \(id)")
            lastClose = Date()
            NSRunningApplication(processIdentifier: w.pid)?.forceTerminate()
            forced.insert(id)
        }
        return forced
    }

    /// The window shows a sheet (a save dialog, most likely), which the user must answer.
    private static func hasSheet(_ w: Window) -> Bool {
        w.element.elements(kAXChildrenAttribute).contains { $0.string(kAXRoleAttribute) == kAXSheetRole }
    }

    /// Windows `closeMarked` no longer keeps hidden: whichever are still open come back on screen.
    private func stopClosing(_ ids: [CGWindowID]) {
        closingNow.subtract(ids)
        releasePending(Set(ids))
        quitWindowless()
    }

    /// Apps whose windows the sort closed and that kept running without any (kitty, by default, stays in the
    /// Dock with no window): quit them, and force quit those that don't go. Finder and apps without a Dock
    /// icon are left alone; an app with a window anywhere (another space, minimized, a sheet) too.
    private func quitWindowless() {
        for pid in closingApps {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { closingApps.remove(pid); continue }
            guard app.activationPolicy == .regular, app.bundleIdentifier != "com.apple.finder" else { closingApps.remove(pid); continue }
            let known = windows.values.contains { $0.pid == pid && $0.isValid }
            guard !known, AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { continue }
            closingApps.remove(pid)
            let name = app.bundleIdentifier ?? "pid \(pid)"
            Log.info("sort: \(name) has no windows left; quitting it")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard !app.isTerminated, AXUIElementCreateApplication(pid).elements(kAXWindowsAttribute).isEmpty else { return }
                Log.info("sort: \(name) didn't quit; force quitting it")
                app.forceTerminate()
            }
        }
    }

    /// The panel was dismissed without keeping anything: put everything back, focus and shown workspaces untouched.
    func revertSort() {
        sortSession = false
        if let u = sortSnapshot { restoreSort(u) }
        sortSnapshot = nil
        releasePending()
    }

    /// Nothing may stay hidden on a workspace that is never shown: windows waiting there (only `ids`, else
    /// all but those being closed right now) go to the workspace their display shows.
    private func releasePending(_ ids: Set<CGWindowID>? = nil) {
        let waiting = workspaceOf.filter { isPending($0.value) && (ids?.contains($0.key) ?? !closingNow.contains($0.key)) }
        let screens = Screen.all()
        for (id, key) in waiting {
            let display = String(key.dropFirst(Self.pendingPrefix.count))
            workspaceOf[id] = virtualShown[display] ?? screens.first.flatMap { virtualShown[$0.uuid] } ?? screens.first.flatMap { shown[$0.uuid] }
        }
        let used = Set(workspaceOf.values.filter(isPending))
        for key in monitorOf.keys where isPending(key) && !used.contains(key) { monitorOf[key] = nil }
        guard !waiting.isEmpty else { return }
        corrections = [:]
        refresh()
    }

    /// The panel went away without a say in the matter (the workspace mode changed under it).
    func endSort() {
        sortSession = false
        releasePending()
    }

    /// Puts everything back as it was when the panel opened (the toast's Undo). Closed windows stay closed.
    @discardableResult
    func undoSort() -> Bool {
        guard config.virtualWorkspaces, !sortSession, let u = sortSnapshot else { return false }
        sortSnapshot = nil
        restoreSort(u)
        return true
    }

    /// Windows being closed keep their place (hidden) so they never flash back on screen.
    private func restoreSort(_ u: SortSnapshot) {
        for (id, ws) in u.workspaceOf where windows[id] != nil && !closingNow.contains(id) { workspaceOf[id] = ws }
        let known = Set(u.order)
        order = u.order.filter { windows[$0] != nil } + order.filter { !known.contains($0) }
        monitorOf = u.monitorOf
        labels = u.labels
        for name in Array(states.keys) where u.layouts[name] == nil { states[name] = nil }
        for (name, l) in u.layouts {
            let st = state(workspace: name)
            st.layout = l.layout; st.ratio = l.ratio.isFinite ? min(0.9, max(0.1, l.ratio)) : 0.5; st.mainCount = l.mainCount; st.zoomed = nil
        }
        corrections = [:]
        quietWorkspaceHUD = true
        defer { quietWorkspaceHUD = false }
        for (display, ws) in u.shown where virtualShown[display] != ws { showWorkspace(ws, focus: false) }
        refresh()
    }

    private func tiledCount(in ws: String) -> Int {
        order.reduce(0) { n, id in n + (present.contains(id) && workspaceOf[id] == ws && windows[id]?.isFloating == false ? 1 : 0) }
    }

    /// The workspace a display shows and how many tiled windows it holds; the focused display first.
    func shownWorkspaces() -> [(workspace: String, count: Int, screen: NSScreen)] {
        guard config.virtualWorkspaces, isStarted else { return [] }
        let screens = Screen.all()
        let focus = currentScreen()?.uuid
        return (screens.filter { $0.uuid == focus } + screens.filter { $0.uuid != focus }).compactMap { s in
            guard let ws = shown[s.uuid], isVirtual(ws) else { return nil }
            return (ws, tiledCount(in: ws), s.ns)
        }
    }

    /// Watches for a shown workspace growing past `sort-nudge`, and offers to sort once it has stayed that way.
    private func watchCrowding(_ screens: [Screen]) {
        guard config.virtualWorkspaces, tilingEnabled, config.sortNudge > 0,
              screens.contains(where: { s in shown[s.uuid].map { isVirtual($0) && tiledCount(in: $0) > config.sortNudge } ?? false })
        else { crowdWork?.cancel(); crowdWork = nil; return }
        guard crowdWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            crowdWork = nil
            if let hit = shownWorkspaces().first(where: { $0.count > self.config.sortNudge }) {
                SortNudge.shared.offer(workspace: hit.workspace, count: hit.count, on: hit.screen)
            }
        }
        crowdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
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

    /// Fallback for macOS Spaces mode: hold the window by an empty part of its title bar and switch
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

    /// Diagnostics (`ouch grabtest`): try each grab point on the focused window without
    /// switching spaces, logging which ones pick the window up.
    private func grabTest() {
        guard !movingToSpace, let w = focusedWindow() else { Log.info("grabtest: no focused window"); return }
        let points = grabPoints(for: w, frame: w.frame)
        Log.info("grabtest: \(w.bundleID ?? "pid \(w.pid)") frame \(w.frame) candidates \(points)")
        movingToSpace = true
        let restore = mouseLocation()
        func next(_ rest: ArraySlice<CGPoint>) {
            guard let p = rest.first else { finishMove(restore: restore); return }
            let original = serverFrame(w.id) ?? w.frame
            attemptGrab(w, at: p) { [weak self] grabbed, held in
                self?.postMouse(.leftMouseUp, held)
                Log.info("grabtest: \(p) \(grabbed ? "GRABS" : "no")")
                if grabbed { self?.rememberGrab(w, p, frame: original) }
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
        CursorRefresh.soon()
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
