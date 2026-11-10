import AppKit

final class WindowManager {
    static let shared = WindowManager(config: ConfigStore.shared.load(), scope: Instance.scope)

    let backend: any WindowBackend
    let scope: WindowScope?
    let input: GlobalInput
    var config: Config
    var tilingEnabled = true
    var restoringTemplate = false {
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
    var placementHolds = PlacementHolds()
    var pendingLaunches: [PendingLaunch] = []
    var onChange: (() -> Void)?
    var onDispatch: ((_ dispatcher: String, _ arg: String, _ inMode: Bool) -> Void)?
    var onModeChange: ((String) -> Void)?
    var surface: any TilingSurface = HeadlessSurface()
    var practice: (pid: pid_t, workspaces: [String: String])?
    var keyPostStyle = Hotkeys.PostStyle.physical

    var windows: [CGWindowID: Window] = [:]
    var observedApps: [(pid: pid_t, bundleID: String?)] = []
    let nativeDesktop = NativeDesktopController()
    var desktops = NativeDesktopState()
    let nativeGestures = DesktopGestureTap()
    var nativeMoves = NativeWindowMoves()
    var model = WorkspaceModel()
    var workspaceOf: [CGWindowID: String] { model.workspaceOf }
    var order: [CGWindowID] { get { model.order } set { model.order = newValue } _modify { yield &model.order } }
    var monitorOf: [String: String] {
        get { model.monitorOf } set { model.monitorOf = newValue } _modify { yield &model.monitorOf }
    }
    var shown: [String: String] { get { model.shown } set { model.shown = newValue } _modify { yield &model.shown } }
    var virtualShown: [String: String] {
        get { model.virtualShown } set { model.virtualShown = newValue } _modify { yield &model.virtualShown }
    }
    var states: [String: ScreenState] {
        get { model.states } set { model.states = newValue } _modify { yield &model.states }
    }
    var lastFocused: [String: CGWindowID] {
        get { model.lastFocused } set { model.lastFocused = newValue } _modify { yield &model.lastFocused }
    }
    var focusStamps: [CGWindowID: Int] { model.focusStamps }
    var focusClock: Int { model.focusClock }
    var focusOrder: [CGWindowID] { model.focusOrder }
    var displayOf: [CGWindowID: String] = [:]
    var snapNextPlacement: Set<CGWindowID> = []
    var restoredEarly: [CGWindowID: Date] = [:]
    var present: Set<CGWindowID> = []
    var leavingFullscreen: [CGWindowID: Date] = [:]
    var focusRequests = FocusRequests()
    var closeAndSort = CloseAndSortState()
    var floats = FloatState()
    var previousWorkspace: [String: String] = [:]
    var labels: [String: String] = [:]
    struct Slide {
        let monitor: String
        let workspace: String
        let outgoing: Set<CGWindowID>
        let forward: Bool
        let until: CFTimeInterval
    }
    var slide: Slide?
    var crowdWork: DispatchWorkItem?
    var autoSwitchAfter = Date.distantPast
    var lastSavedWorkspaces = ""
    var tilingRecovery = TilingRecovery()
    var tabUI = TabInteraction()
    var lastSavedTilingRecovery = TilingRecovery()
    var startedAt = Date.distantPast
    var poweringOffAt = Date.distantPast
    var focusSink: NSWindow?
    var visible: Set<CGWindowID> = []
    var targets: [CGWindowID: CGRect] = [:]
    var frontmostPID: () -> pid_t?
    var frameReads: [CGWindowID: UUID] = [:]
    var dirtyFrames: Set<CGWindowID> = []
    var observing: [pid_t: UUID] = [:]
    var observers: [pid_t: AXObserver] = [:]
    var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    var drags: [CGWindowID: Bool] = [:]
    var refreshWork: DispatchWorkItem?
    var scanRequests = 0
    var scanWaiters: [(request: Int, done: () -> Void)] = []
    var minSizes: [CGWindowID: CGSize] = [:]
    struct MenuBarFloor {
        let height: CGFloat
        let visible: CGRect
        func height(on visible: CGRect) -> CGFloat? { visible == self.visible ? height : nil }
    }
    var menuBarHeights: [String: MenuBarFloor] = [:]
    var dividerState = DividerState()
    var refreshDeadline = DispatchTime.distantFuture
    var isStarted = false
    var ignoreMouseUntil = Date.distantPast
    var animator: Animator
    var notificationObservers: [NSObjectProtocol] = []
    let scanner: WindowScanner
    let dockWindowPull = DockWindowPull()
    let dockArea = DockArea()
    let cursorRefresh: CursorRefresh
    var warp: (CGPoint) -> Void = { CGWarpMouseCursorPosition($0) }

    init(backend: any WindowBackend = AXBackend.shared, config: Config, scope: WindowScope? = nil,
         scanner: WindowScanner? = nil) {
        self.backend = backend
        self.scope = scope
        input = GlobalInput(scope: scope, keys: Instance.keys)
        self.config = scope?.restrict(config) ?? config
        frontmostPID = { backend.frontmostPID() }
        animator = Animator(backend: backend)
        cursorRefresh = CursorRefresh(backend: backend)
        self.scanner = scanner ?? WindowScanner(
            read: { backend.scan($0, discovered: $1) }, readDesktop: { backend.desktop(known: $0) },
            readApplications: { backend.applications() }, scope: scope,
            claims: scope == nil ? ScopeClaims(folder: Instance.paths.instancesFolder) : nil)
        focusRequests.focusReader = FocusReader { backend.focusedWindow(pid: $0) }
    }

    func scopeRefusal(_ command: String) -> String? {
        guard let scope, !scope.allows(command) else { return nil }
        let name = WindowActions.named(command)?.name ?? command
        return "`\(name)` is not available in a scoped instance: "
            + "it would act on windows, Desktops or input outside the scope"
    }

    func warpPointer(to point: CGPoint) {
        guard input.pointerAndFocus else { return }
        warp(point)
        cursorRefresh.soon()
    }

    var currentLayoutTitle: String {
        guard let screen = currentScreen() else { return "" }
        return state(for: screen).layout.title
    }

    lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = Instance.defaults.dictionary(forKey: DefaultsKey.grabHints) as? [String: [Double]] ?? [:]
        return saved.compactMapValues { values in
            values.count == 4 ? (CGPoint(x: values[0], y: values[1]), CGPoint(x: values[2], y: values[3])) : nil
        }
    }()
}
