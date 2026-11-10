import CoreGraphics

package struct WorkspaceModel {
    package private(set) var workspaceOf: [CGWindowID: String] = [:]
    package var order: [CGWindowID] = []
    package var monitorOf: [String: String] = [:]
    package var shown: [String: String] = [:] {
        didSet { shownSet = Set(shown.values) }
    }
    package var virtualShown: [String: String] = [:]
    package var states: [String: ScreenState] = [:]
    package var lastFocused: [String: CGWindowID] = [:]
    package var fullscreenHost: [String: CGWindowID] = [:]
    package var focusStamps: [CGWindowID: Int] = [:]
    package var focusClock = 0
    package var focusOrder: [CGWindowID] = []
    package var tabs = TabGroups()
    package var maximisedTabs: [CGWindowID: MaximisedTab] = [:]
    package private(set) var shownSet: Set<String> = []

    package func isShown(_ workspace: String?) -> Bool { workspace.map(shownSet.contains) ?? false }

    package mutating func assign(_ id: CGWindowID, to workspace: String?) {
        if workspaceOf[id] != workspace,
           tabs.group(of: id)?.members.contains(where: { $0 != id && workspaceOf[$0] != workspace }) == true {
            leaveTab(id)
        }
        workspaceOf[id] = workspace
    }

    package mutating func assign(_ moves: [CGWindowID: String]) {
        for (id, workspace) in moves { workspaceOf[id] = workspace }
        for group in tabs.groups where group.members.contains(where: { moves[$0] != nil }) {
            let homes = group.members.map { workspaceOf[$0] }
            let lead = workspaceOf[group.active]
            func score(_ home: String?) -> (Int, Int) { (homes.filter { $0 == home }.count, home == lead ? 1 : 0) }
            let home = homes.max { score($0) < score($1) } ?? lead
            for member in group.members where workspaceOf[member] != home { leaveTab(member) }
        }
    }

    package mutating func swapWorkspaces(_ first: CGWindowID, _ second: CGWindowID) {
        if workspaceOf[first] != workspaceOf[second] { leaveTab(first); leaveTab(second) }
        (workspaceOf[first], workspaceOf[second]) = (workspaceOf[second], workspaceOf[first])
    }

    package mutating func forget(_ id: CGWindowID) {
        leaveTab(id)
        workspaceOf[id] = nil
        order.removeAll { $0 == id }
        focusStamps[id] = nil
        focusOrder.removeAll { $0 == id }
        lastFocused = lastFocused.filter { $0.value != id }
        fullscreenHost = fullscreenHost.filter { $0.value != id }
        maximisedTabs[id] = nil
    }

    package mutating func show(_ workspace: String?, on display: String) { shown[display] = workspace }

    package mutating func resetWorkspaces() {
        workspaceOf = [:]; monitorOf = [:]; shown = [:]; virtualShown = [:]
        states = [:]; lastFocused = [:]; fullscreenHost = [:]; tabs = TabGroups(); maximisedTabs = [:]
    }

    package mutating func noteFocus(_ id: CGWindowID) {
        if focusStamps[id] != focusClock {
            focusClock += 1
            focusStamps[id] = focusClock
        }
        focusOrder.removeAll { $0 == id }
        focusOrder.insert(id, at: 0)
        if focusOrder.count > 80 { focusOrder.removeLast(focusOrder.count - 80) }
    }

    package func mostRecent<S: Sequence>(of ids: S) -> CGWindowID? where S.Element == CGWindowID {
        guard let id = ids.max(by: { (focusStamps[$0] ?? 0) < (focusStamps[$1] ?? 0) }),
              focusStamps[id] != nil else { return nil }
        return id
    }

    package func snapshot() -> WorkspaceModel {
        var copy = self
        copy.states = states.mapValues { $0.copy() }
        return copy
    }
}

package enum WorkspaceKey {
    package static func make(_ number: String, on display: String, perDisplay: Bool) -> String {
        perDisplay ? "\(display)/\(number)" : number
    }

    package static func display(_ key: String) -> String? {
        key.lastIndex(of: "/").map { String(key[..<$0]) }
    }

    package static func number(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? key
    }
}
