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
    var focusStamps: [CGWindowID: Int] = [:]
    var focusClock = 0
    var focusOrder: [CGWindowID] = []
    private(set) var shownSet: Set<String> = []

    func isShown(_ ws: String?) -> Bool { ws.map(shownSet.contains) ?? false }

    mutating func assign(_ id: CGWindowID, to ws: String?) { workspaceOf[id] = ws }

    mutating func swapWorkspaces(_ a: CGWindowID, _ b: CGWindowID) {
        (workspaceOf[a], workspaceOf[b]) = (workspaceOf[b], workspaceOf[a])
    }

    mutating func keepWorkspaces(where keep: (String) -> Bool) { workspaceOf = workspaceOf.filter { keep($0.value) } }

    mutating func forget(_ id: CGWindowID) {
        workspaceOf[id] = nil
        order.removeAll { $0 == id }
        focusStamps[id] = nil
        focusOrder.removeAll { $0 == id }
        lastFocused = lastFocused.filter { $0.value != id }
    }

    mutating func show(_ ws: String?, on display: String) { shown[display] = ws }

    mutating func resetWorkspaces() {
        workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]; states = [:]; lastFocused = [:]
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
        guard let id = ids.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }), focusStamps[id] != nil else { return nil }
        return id
    }

    func snapshot() -> WorkspaceModel {
        var copy = self
        copy.states = states.mapValues { $0.copy() }
        return copy
    }
}
