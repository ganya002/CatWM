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
    var onDispatch: ((_ dispatcher: String, _ arg: String, _ inMode: Bool) -> Void)?
    var onModeChange: ((String) -> Void)?
    var practice: (pid: pid_t, workspaces: [String: String])?

    var windows: [CGWindowID: Window] = [:]
    var order: [CGWindowID] = []
    var workspaceOf: [CGWindowID: String] = [:]
    var monitorOf: [String: String] = [:]
    var shown: [String: String] = [:]
    var virtualShown: [String: String] = [:]
    var homeSpace: [String: UInt64] = [:]
    var displayOf: [CGWindowID: String] = [:]
    var workspaceMoves: Set<CGWindowID> = []
    var snapNextPlacement: Set<CGWindowID> = []
    var present: Set<CGWindowID> = []
    var lastFocused: [String: CGWindowID] = [:]
    var focusStamps: [CGWindowID: Int] = [:]
    var focusClock = 0
    var pendingFocus: (id: CGWindowID, until: Date)?
    var refocusAfterClose: String?
    var lastClose = Date.distantPast
    var floatFrames: [CGWindowID: CGRect] = [:]
    var savedWorkspaceOf: [CGWindowID: String] = [:]
    var savedOwnerOf: [CGWindowID: String] = [:]
    var savedFloating: [CGWindowID: Bool] = [:]
    var previousWorkspace: [String: String] = [:]
    var labels: [String: String] = [:]
    var focusOrder: [CGWindowID] = []
    var sortSnapshot: SortSnapshot?
    var closingNow: Set<CGWindowID> = []
    var closingApps: Set<pid_t> = []
    var sortSession = false
    var quietWorkspaceHUD = false
    struct Slide {
        let monitor: String
        let to: String
        let outgoing: Set<CGWindowID>
        let forward: Bool
        let until: CFTimeInterval
    }
    var slide: Slide?
    var crowdWork: DispatchWorkItem?
    var autoSwitchAfter = Date.distantPast
    var lastSavedWorkspaces = ""
    var focusSink: NSWindow?
    var visible: Set<CGWindowID> = []
    var targets: [CGWindowID: CGRect] = [:]
    var states: [String: ScreenState] = [:]
    var observers: [pid_t: AXObserver] = [:]
    var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    var drags: [CGWindowID: Bool] = [:]
    var refreshWork: DispatchWorkItem?
    var ffmWork: DispatchWorkItem?
    var minSizes: [CGWindowID: CGSize] = [:]
    var ratioChange: (screen: String, until: Date)?
    var refreshDeadline = DispatchTime.distantFuture
    private(set) var isStarted = false
    var ignoreMouseUntil = Date.distantPast
    var movingToSpace = false
    var pendingSpace: (display: String, index: Int, until: Date)?
    var spaceGeneration = 0
    let animator = Animator()
    let scanner = WindowScanner()
    private let dockWindowPull = DockWindowPull()
    let dockArea = DockArea()


    func start() {
        guard !isStarted else { return }
        isStarted = true
        loadWorkspaces()
        Log.verbose = config.debugLogging || Log.verboseLaunch
        Log.info("start: trusted=\(AXIsProcessTrusted()) windowServerFocus=\(WindowServerFocus.isAvailable) screens=\(Screen.all().count)")
        config.errors.forEach { Log.info("config: \($0)") }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        animator.onMinimumSize = { [weak self] id, size in self?.learnMinimum(id, size) }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            for delay in [0.3, 1.0, 2.5] {
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
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.pendingFocus = nil
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

        DistributedNotificationCenter.default().addObserver(forName: ipcNotification, object: nil, queue: .main) { [weak self] n in
            if let cmd = n.object as? String { self?.ipc(cmd) }
        }

        refresh()
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


    lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = UserDefaults.standard.dictionary(forKey: "grabHints") as? [String: [Double]] ?? [:]
        return saved.compactMapValues { v in
            v.count == 4 ? (CGPoint(x: v[0], y: v[1]), CGPoint(x: v[2], y: v[3])) : nil
        }
    }()
}
