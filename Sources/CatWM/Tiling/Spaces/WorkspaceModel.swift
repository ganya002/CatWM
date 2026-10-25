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
    var tabs = TabGroups()
    var maximisedTabs: [CGWindowID: MaximisedTab] = [:]
    private(set) var shownSet: Set<String> = []

    func isShown(_ workspace: String?) -> Bool { workspace.map(shownSet.contains) ?? false }

    mutating func assign(_ id: CGWindowID, to workspace: String?) {
        if workspaceOf[id] != workspace,
           tabs.group(of: id)?.members.contains(where: { $0 != id && workspaceOf[$0] != workspace }) == true {
            leaveTab(id)
        }
        workspaceOf[id] = workspace
    }

    mutating func assign(_ moves: [CGWindowID: String]) {
        for (id, workspace) in moves { workspaceOf[id] = workspace }
        for group in tabs.groups where group.members.contains(where: { moves[$0] != nil }) {
            let homes = group.members.map { workspaceOf[$0] }
            let lead = workspaceOf[group.active]
            func score(_ home: String?) -> (Int, Int) { (homes.filter { $0 == home }.count, home == lead ? 1 : 0) }
            let home = homes.max { score($0) < score($1) } ?? lead
            for member in group.members where workspaceOf[member] != home { leaveTab(member) }
        }
    }

    mutating func swapWorkspaces(_ first: CGWindowID, _ second: CGWindowID) {
        if workspaceOf[first] != workspaceOf[second] { leaveTab(first); leaveTab(second) }
        (workspaceOf[first], workspaceOf[second]) = (workspaceOf[second], workspaceOf[first])
    }

    mutating func forget(_ id: CGWindowID) {
        leaveTab(id)
        workspaceOf[id] = nil
        order.removeAll { $0 == id }
        focusStamps[id] = nil
        focusOrder.removeAll { $0 == id }
        lastFocused = lastFocused.filter { $0.value != id }
        fullscreenHost = fullscreenHost.filter { $0.value != id }
        maximisedTabs[id] = nil
    }

    mutating func show(_ workspace: String?, on display: String) { shown[display] = workspace }

    mutating func resetWorkspaces() {
        workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]
        states = [:]; lastFocused = [:]; fullscreenHost = [:]; tabs = TabGroups(); maximisedTabs = [:]
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

enum WorkspaceKey {
    static func make(_ number: String, on display: String, perDisplay: Bool) -> String {
        perDisplay ? "\(display)/\(number)" : number
    }

    static func display(_ key: String) -> String? {
        key.lastIndex(of: "/").map { String(key[..<$0]) }
    }

    static func number(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? key
    }
}
