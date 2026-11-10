import AppKit

package final class WindowManager {
    private final class Slot {
        private let lock = NSLock()
        private var installed: WindowManager?
        private var standalone: WindowManager?

        var manager: WindowManager {
            lock.withLock {
                if let manager = installed ?? standalone { return manager }
                let manager = WindowManager(config: ConfigStore.shared.load(), scope: Instance.scope)
                standalone = manager
                return manager
            }
        }

        func install(_ manager: WindowManager) { lock.withLock { installed = manager } }
    }

    private static let slot = Slot()
    package static var shared: WindowManager { slot.manager }
    package static func install(_ manager: WindowManager) { slot.install(manager) }

    package let backend: any WindowBackend
    package let scope: WindowScope?
    package let embedded: Bool
    package let input: GlobalInput
    package var config: Config
    package lazy var store = ConfigStore.shared
    package var socketPath = ControlServer.socketPath
    package var tilingEnabled = true
    package var restoringTemplate = false {
        didSet {
            if restoringTemplate {
                tilingRecovery = TilingRecovery()
                refreshWork?.cancel()
                refreshWork = nil
                refreshDeadline = .distantFuture
                for id in windows.keys { animator.cancel(id) }
            }
        }
    }
    package var placementHolds = PlacementHolds()
    package var pendingLaunches: [PendingLaunch] = []
    package var onChange: (() -> Void)?
    package var onDispatch: ((_ dispatcher: String, _ arg: String, _ inMode: Bool) -> Void)?
    package var onModeChange: ((String) -> Void)?
    package var surface: any TilingSurface = HeadlessSurface()
    package var practice: (pid: pid_t, workspaces: [String: String])?
    package var keyPostStyle = Hotkeys.PostStyle.physical

    package var windows: [CGWindowID: Window] = [:]
    package var observedApps: [(pid: pid_t, bundleID: String?)] = []
    package let nativeDesktop = NativeDesktopController()
    package var desktops = NativeDesktopState()
    package let nativeGestures = DesktopGestureTap()
    package var nativeMoves = NativeWindowMoves()
    package var model = WorkspaceModel()
    package var workspaceOf: [CGWindowID: String] { model.workspaceOf }
    package var order: [CGWindowID] {
        get { model.order } set { model.order = newValue } _modify { yield &model.order }
    }
    package var monitorOf: [String: String] {
        get { model.monitorOf } set { model.monitorOf = newValue } _modify { yield &model.monitorOf }
    }
    package var shown: [String: String] {
        get { model.shown } set { model.shown = newValue } _modify { yield &model.shown }
    }
    package var virtualShown: [String: String] {
        get { model.virtualShown } set { model.virtualShown = newValue } _modify { yield &model.virtualShown }
    }
    package var states: [String: ScreenState] {
        get { model.states } set { model.states = newValue } _modify { yield &model.states }
    }
    package var lastFocused: [String: CGWindowID] {
        get { model.lastFocused } set { model.lastFocused = newValue } _modify { yield &model.lastFocused }
    }
    package var focusStamps: [CGWindowID: Int] { model.focusStamps }
    package var focusClock: Int { model.focusClock }
    package var focusOrder: [CGWindowID] { model.focusOrder }
    package var displayOf: [CGWindowID: String] = [:]
    package var snapNextPlacement: Set<CGWindowID> = []
    package var restoredEarly: [CGWindowID: Date] = [:]
    package var present: Set<CGWindowID> = []
    package var leavingFullscreen: [CGWindowID: Date] = [:]
    package var focusRequests = FocusRequests()
    package var closeAndSort = CloseAndSortState()
    package var floats = FloatState()
    package var previousWorkspace: [String: String] = [:]
    package var labels: [String: String] = [:]
    package struct Slide {
        package let monitor: String
        package let workspace: String
        package let outgoing: Set<CGWindowID>
        package let forward: Bool
        package let until: CFTimeInterval
    }
    package var slide: Slide?
    package var crowdWork: DispatchWorkItem?
    package var autoSwitchAfter = Date.distantPast
    package var lastSavedWorkspaces = ""
    package var tilingRecovery = TilingRecovery()
    package var tabUI = TabInteraction()
    package var lastSavedTilingRecovery = TilingRecovery()
    package var startedAt = Date.distantPast
    package var poweringOffAt = Date.distantPast
    package var focusSink: NSWindow?
    package var visible: Set<CGWindowID> = []
    package var targets: [CGWindowID: CGRect] = [:]
    package var frontmostPID: () -> pid_t?
    package var frameReads: [CGWindowID: UUID] = [:]
    package var dirtyFrames: Set<CGWindowID> = []
    package var observing: [pid_t: UUID] = [:]
    package var observers: [pid_t: AXObserver] = [:]
    package var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    package var drags: [CGWindowID: Bool] = [:]
    package var refreshWork: DispatchWorkItem?
    package var scanRequests = 0
    package var scanWaiters: [(request: Int, done: () -> Void)] = []
    package var minSizes: [CGWindowID: CGSize] = [:]
    package struct MenuBarFloor {
        package let height: CGFloat
        package let visible: CGRect
        package func height(on visible: CGRect) -> CGFloat? { visible == self.visible ? height : nil }
    }
    package var menuBarHeights: [String: MenuBarFloor] = [:]
    package var dividerState = DividerState()
    package var refreshDeadline = DispatchTime.distantFuture
    package var isStarted = false
    package var servicesStarted = false
    package var mayTile: () -> Bool = { true }
    package var ignoreMouseUntil = Date.distantPast
    package var animator: Animator
    package var notificationObservers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    package var eventMonitors: [Any] = []
    package let scanner: WindowScanner
    package let dockWindowPull = DockWindowPull()
    package let dockArea = DockArea()
    package let cursorRefresh: CursorRefresh
    package var warp: (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) }

    package init(backend: any WindowBackend = AXBackend.shared, config: Config, scope: WindowScope? = nil,
                 scanner: WindowScanner? = nil, embedded: Bool = false) {
        self.backend = backend
        self.scope = scope
        self.embedded = embedded
        nativeDesktop.guarded = !embedded
        input = GlobalInput(scope: scope, keys: Instance.keys, embedded: embedded)
        self.config = Self.effective(config, scope: scope)
        frontmostPID = { backend.frontmostPID() }
        animator = Animator(backend: backend)
        cursorRefresh = CursorRefresh(backend: backend)
        self.scanner = scanner ?? WindowScanner(
            read: { backend.scan($0, discovered: $1) }, readDesktop: { backend.desktop(known: $0) },
            readApplications: { backend.applications() }, scope: scope,
            claims: scope == nil ? ScopeClaims(folder: Instance.paths.instancesFolder) : nil)
        focusRequests.focusReader = FocusReader { backend.focusedWindow(pid: $0) }
    }

    package func scopeRefusal(_ command: String) -> String? {
        let name = WindowActions.named(command)?.name ?? command
        if embedded, name == WindowActions.exit.name {
            return "`exit` is not available in embedded mode: the host owns the process"
        }
        if let feature = Self.feature(of: name), !config.features.contains(feature) {
            return "`\(name)` needs `\(feature.path)`, which is off"
        }
        guard let scope, !scope.allows(command) else { return nil }
        return "`\(name)` is not available in a scoped instance: "
            + "it would act on windows, Desktops or input outside the scope"
    }

    package static func feature(of command: String) -> Feature? {
        if command == WindowActions.switcher.name { return .switcher }
        return switch WindowActions.named(command)?.group {
        case "tabs": .tabGroups
        case "overview": .overview
        case "window", "layout", "workspaces", "focus", "displays": .tiling
        default: nil
        }
    }

    package static func effective(_ config: Config, scope: WindowScope?) -> Config {
        var config = scope?.restrict(config) ?? config
        let features = config.features
        if !features.contains(.desktops) { config.virtualWorkspaces = false }
        if !features.contains(.mouse) {
            config.mouseSwapsWindows = false
            config.mouseResizesWindows = false
        }
        if !features.contains(.cursorActions) { config.cursorActions = false }
        if !features.contains(.notifications) { config.tabNotificationBadges = false }
        if !features.contains(.dimming) {
            config.dimOtherWindows = false
            config.blurOtherWindows = false
        }
        if !features.contains(.keyHelp) { config.keyboardHelp = false }
        if !features.contains(.hud) {
            config.enablesLayoutHUD = false
            config.enablesLayoutHUDOnSpaceChange = false
        }
        return config
    }

    package func warpPointer(to point: CGPoint) {
        guard input.pointerAndFocus else { return }
        warp(point)
        cursorRefresh.soon()
    }

    package var currentLayoutTitle: String {
        guard let screen = currentScreen() else { return "" }
        return state(for: screen).layout.title
    }

    package lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = Instance.defaults.dictionary(forKey: DefaultsKey.grabHints) as? [String: [Double]] ?? [:]
        return saved.compactMapValues { values in
            values.count == 4 ? (CGPoint(x: values[0], y: values[1]), CGPoint(x: values[2], y: values[3])) : nil
        }
    }()
}
