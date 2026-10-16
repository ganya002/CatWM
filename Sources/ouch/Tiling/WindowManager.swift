// Tiling: WindowManager core state and lifecycle. Its features live in the WindowManager+*.swift extensions.
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

    func copy() -> ScreenState {
        let c = ScreenState(layout: layout)
        c.ratio = ratio; c.mainCount = mainCount; c.zoomed = zoomed
        return c
    }
}

let ipcNotification = Notification.Name("local.ouch.command")

final class FocusSinkWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

func axCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString,
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

    var windows: [CGWindowID: Window] = [:]
    // Workspaces. In virtual mode these are Ouch's own (windows on hidden workspaces are parked
    // off-screen); in macOS-Spaces mode each display's current Space is treated as its workspace.
    // The bookkeeping lives in `model`; the properties below forward to it (see `WorkspaceModel`).
    var model = WorkspaceModel()
    var workspaceOf: [CGWindowID: String] { model.workspaceOf } // change it with `model.assign`
    var order: [CGWindowID] { get { model.order } set { model.order = newValue } _modify { yield &model.order } }
    var monitorOf: [String: String] { get { model.monitorOf } set { model.monitorOf = newValue } _modify { yield &model.monitorOf } }
    var shown: [String: String] { get { model.shown } set { model.shown = newValue } _modify { yield &model.shown } }
    var virtualShown: [String: String] {
        get { model.virtualShown } set { model.virtualShown = newValue } _modify { yield &model.virtualShown }
    }
    var states: [String: ScreenState] { get { model.states } set { model.states = newValue } _modify { yield &model.states } }
    var lastFocused: [String: CGWindowID] {
        get { model.lastFocused } set { model.lastFocused = newValue } _modify { yield &model.lastFocused }
    }
    var focusStamps: [CGWindowID: Int] { model.focusStamps } // change it with `model.noteFocus` / `model.forget`
    var focusClock: Int { model.focusClock }
    var focusOrder: [CGWindowID] { model.focusOrder }
    var homeSpace: [String: UInt64] = [:]        // display UUID → the macOS Space workspaces live on
    var displayOf: [CGWindowID: String] = [:]    // display UUID each window was last seen on (see `syncWorkspaces`)
    var workspaceMoves: Set<CGWindowID> = []
    var snapNextPlacement: Set<CGWindowID> = []
    var present: Set<CGWindowID> = []
    /// A window we just focused. macOS takes a moment to report it, and a key press in between
    /// must navigate from it, not from the window before (or spamming a key goes nowhere).
    var pendingFocus: (id: CGWindowID, until: Date)?
    var refocusAfterClose: String? // workspace whose focused window just closed
    var lastClose = Date.distantPast // when a window last closed (macOS then refocuses the previous app's window)
    var floatFrames: [CGWindowID: CGRect] = [:]  // floating windows' frames while parked
    var savedWorkspaceOf: [CGWindowID: String] = [:]
    var savedOwnerOf: [CGWindowID: String] = [:]  // "pid bundleID" when saved; window IDs are reused after a logout
    var savedFloating: [CGWindowID: Bool] = [:]  // windows floated or tiled by hand, from the last run
    var previousWorkspace: [String: String] = [:] // display UUID → workspace it showed before
    var labels: [String: String] = [:]           // workspace → the name the Sort panel gave it
    var sortSnapshot: SortSnapshot?
    var closingNow: Set<CGWindowID> = []          // closed by a finished sort, kept hidden until checked
    var closingApps: Set<pid_t> = []              // apps of those windows, quit if the sort leaves them windowless
    /// The Sort panel is open: workspaces change under it, but nothing may take the keyboard or switch workspace.
    var sortSession = false
    var quietWorkspaceHUD = false
    /// A workspace swap in progress: leaving windows slide out, arriving ones slide in (see `beginSlide`).
    struct Slide {
        let monitor: String           // display UUID the swap happens on
        let to: String                // workspace arriving
        let outgoing: Set<CGWindowID> // windows leaving
        let forward: Bool             // the new workspace sorts later: leaving windows go left, arriving ones come from the right
        let until: CFTimeInterval     // when the slide is done
    }
    var slide: Slide?
    var crowdWork: DispatchWorkItem?
    var autoSwitchAfter = Date.distantPast
    var lastSavedWorkspaces = ""
    var focusSink: NSWindow?
    var visible: Set<CGWindowID> = []       // managed windows on the current space(s)
    var targets: [CGWindowID: CGRect] = [:] // slot each tiled window was last given
    var observers: [pid_t: AXObserver] = [:]
    var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    var drags: [CGWindowID: Bool] = [:]     // window -> was resized (vs. only moved)
    var refreshWork: DispatchWorkItem?
    var ffmWork: DispatchWorkItem?
    var minSizes: [CGWindowID: CGSize] = [:] // learned from windows that refuse to shrink
    var ratioChange: (screen: String, until: Date)? // a split resize whose windows are still settling
    var refreshDeadline = DispatchTime.distantFuture
    private(set) var isStarted = false
    var ignoreMouseUntil = Date.distantPast
    var movingToSpace = false
    /// Where an in-flight space switch is heading. macOS keeps reporting the old space until the
    /// slide finishes, so quick repeated presses must count from here or they overshoot.
    var pendingSpace: (display: String, index: Int, until: Date)?
    var spaceGeneration = 0
    let animator = Animator()
    let scanner = WindowScanner()
    private let dockWindowPull = DockWindowPull()
    let dockArea = DockArea()

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info("start: trusted=\(Permission.accessibility.isGranted) windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(Screen.all().count)")
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
            ModeCursor.shared.setActive(!name.isEmpty)
            KeyHelp.shared.modeChanged(name)
            CursorActions.shared.modeChanged(name)
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
        CursorActions.shared.install()
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
            model.resetWorkspaces()
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

    // MARK: - Spaces state

    /// Where a grab last worked for each app, measured from the window's top-left and top-right
    /// corners, so the next move tries it first.
    lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = UserDefaults.standard.dictionary(forKey: "grabHints") as? [String: [Double]] ?? [:]
        return saved.compactMapValues { v in
            v.count == 4 ? (CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3])) : nil
        }
    }()
}
