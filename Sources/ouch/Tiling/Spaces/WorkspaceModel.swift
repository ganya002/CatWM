import CoreGraphics

struct WorkspaceModel {
    private(set) var workspaceOf: [CGWindowID: String] = [:]
    var order: [CGWindowID] = []
    var monitorOf: [String: String] = [:]
    var shown: [String: String] = [:] {
        didSet { shownSet = Set(shown.values) }
    }
    var virtualShown: [String: String] = [:]
    var states: [String: ScreenState] = [:]
    var lastFocused: [String: CGWindowID] = [:]
    var fullscreenHost: [String: CGWindowID] = [:]
    var focusStamps: [CGWindowID: Int] = [:]
    var focusClock = 0
    var focusOrder: [CGWindowID] = []
    private(set) var shownSet: Set<String> = []

    func isShown(_ workspace: String?) -> Bool { workspace.map(shownSet.contains) ?? false }

    func isFullscreenWorkspace(_ workspace: String?) -> Bool { workspace.map { fullscreenHost[$0] != nil } ?? false }

    mutating func assign(_ id: CGWindowID, to workspace: String?) { workspaceOf[id] = workspace }

    mutating func swapWorkspaces(_ first: CGWindowID, _ second: CGWindowID) {
        (workspaceOf[first], workspaceOf[second]) = (workspaceOf[second], workspaceOf[first])
    }

    mutating func keepWorkspaces(where keep: (String) -> Bool) { workspaceOf = workspaceOf.filter { keep($0.value) } }

    mutating func forget(_ id: CGWindowID) {
        workspaceOf[id] = nil
        order.removeAll { $0 == id }
        focusStamps[id] = nil
        focusOrder.removeAll { $0 == id }
        lastFocused = lastFocused.filter { $0.value != id }
        fullscreenHost = fullscreenHost.filter { $0.value != id }
    }

    mutating func show(_ workspace: String?, on display: String) { shown[display] = workspace }

    mutating func resetWorkspaces() {
        workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]
        states = [:]; lastFocused = [:]; fullscreenHost = [:]
    }

    mutating func noteFocus(_ id: CGWindowID) {
        if focusStamps[id] != focusClock {
            focusClock += 1
            focusStamps[id] = focusClock
        }
        focusOrder.removeAll { $0 == id }
        focusOrder.insert(id, at: 0)
        if focusOrder.count > 80 { focusOrder.removeLast(focusOrder.count - 80) }
    }

    func mostRecent<S: Sequence>(of ids: S) -> CGWindowID? where S.Element == CGWindowID {
        guard let id = ids.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }),
              focusStamps[id] != nil else { return nil }
        return id
    }

    func snapshot() -> WorkspaceModel {
        var copy = self
        copy.states = states.mapValues { $0.copy() }
        return copy
    }
}
