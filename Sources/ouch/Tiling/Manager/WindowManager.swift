import AppKit

final class WindowManager {
    static let shared = WindowManager()

    var config = Config.load()
    var tilingEnabled = true
    var restoringTemplate = false {
        didSet {
            if restoringTemplate {
                refreshWork?.cancel()
                refreshWork = nil
                refreshDeadline = .distantFuture
                for id in windows.keys { animator.cancel(id) }
            }
        }
    }
    var templateHiddenWindows: [CGWindowID: Date] = [:]
    var onChange: (() -> Void)?
    var onDispatch: ((_ dispatcher: String, _ arg: String, _ inMode: Bool) -> Void)?
    var onModeChange: ((String) -> Void)?
    var practice: (pid: pid_t, workspaces: [String: String])?

    var windows: [CGWindowID: Window] = [:]
    var observedApps: [(pid: pid_t, bundleID: String?)] = []
    var lastNativeCatalogSaved: [String: UInt64] = [:]
    var nativeCatalog = NativeWorkspaceCatalog()
    let nativeDesktop = NativeDesktopController()
    let nativeGestures = DesktopGestureTap()
    var nativeGestureSign: Double?
    var nativeMigration: [CGWindowID: String] = [:]
    var nativeCreationBusy = false
    var nativeWorkspaceGeneration = 0
    var nativeSortNames: Set<String> = []
    var nativeDroppedWorkspaces: Set<String> = []
    var nativeMoveTargets: [CGWindowID: String] = [:]
    var nativeMembership: [CGWindowID: UInt64] = [:]
    struct FollowMove {
        let window: Window
        let workspace: String
        let space: UInt64
        let from: String?
    }
    var followMoves: [CGWindowID: FollowMove] = [:]
    var arrivals: [CGWindowID: CGRect] = [:]
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
    var homeSpace: [String: UInt64] = [:]
    var displayOf: [CGWindowID: String] = [:]
    var workspaceMoves: Set<CGWindowID> = []
    var snapNextPlacement: Set<CGWindowID> = []
    var restoredEarly: [CGWindowID: Date] = [:]
    var present: Set<CGWindowID> = []
    var leavingFullscreen: [CGWindowID: Date] = [:]
    struct PendingFocus {
        let id: CGWindowID
        let pid: pid_t
        let origin: pid_t?
        let request: UUID
        var executed = false
    }
    struct FocusCommand {
        let pid: pid_t
        let dispatcher: String
        let arg: String
        let inMode: Bool
    }
    var pendingFocus: PendingFocus?
    var focusCommands: [FocusCommand] = []
    var waitingRefocus: (workspace: String, pid: pid_t)?
    var refocusAfterClose: String?
    var lastClose = Date.distantPast
    var floatFrames: [CGWindowID: CGRect] = [:]
    var savedWorkspaceOf: [CGWindowID: String] = [:]
    var savedOwnerOf: [CGWindowID: String] = [:]
    var savedFloating: [CGWindowID: Bool] = [:]
    var previousWorkspace: [String: String] = [:]
    var labels: [String: String] = [:]
    var sortSnapshot: SortSnapshot?
    var closingNow: Set<CGWindowID> = []
    var closingApps: Set<pid_t> = []
    var sortSession = false
    var quietWorkspaceHUD = false
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
    var focusSink: NSWindow?
    var visible: Set<CGWindowID> = []
    var targets: [CGWindowID: CGRect] = [:]
    var reportedFocus: (pid: pid_t, id: CGWindowID?)?
    var frontmostPID: () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    var focusReader = FocusReader()
    var focusObservation = 0
    var focusReads: Set<pid_t> = []
    var frameReads: [CGWindowID: UUID] = [:]
    var dirtyFrames: Set<CGWindowID> = []
    var observing: [pid_t: UUID] = [:]
    var observers: [pid_t: AXObserver] = [:]
    var corrections: [CGWindowID: (target: CGRect, count: Int)] = [:]
    var drags: [CGWindowID: Bool] = [:]
    var refreshWork: DispatchWorkItem?
    var ffmWork: DispatchWorkItem?
    var minSizes: [CGWindowID: CGSize] = [:]
    var ratioChange: (screen: String, until: Date)?
    struct DividerDrag {
        let screen: String
        let startRatio: CGFloat
        var position: CGFloat?
    }
    var dividerDrag: DividerDrag?
    var refreshDeadline = DispatchTime.distantFuture
    var isStarted = false
    var ignoreMouseUntil = Date.distantPast
    var movingToSpace = false
    struct PendingSpace {
        let display: String
        let index: Int
        let until: Date
    }
    var pendingSpace: PendingSpace?
    var spaceGeneration = 0
    var animator = Animator()
    var notificationObservers: [NSObjectProtocol] = []
    let scanner = WindowScanner()
    let dockWindowPull = DockWindowPull()
    let dockArea = DockArea()

    var currentLayoutTitle: String {
        guard let screen = currentScreen() else { return "" }
        return state(for: screen).layout.title
    }

    lazy var grabHints: [String: (fromLeft: CGPoint, fromRight: CGPoint)] = {
        let saved = UserDefaults.standard.dictionary(forKey: "grabHints") as? [String: [Double]] ?? [:]
        return saved.compactMapValues { values in
            values.count == 4 ? (CGPoint(x: values[0], y: values[1]), CGPoint(x: values[2], y: values[3])) : nil
        }
    }()
}
