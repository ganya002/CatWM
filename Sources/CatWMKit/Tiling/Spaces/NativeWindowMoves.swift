import CoreGraphics

package struct NativeWindowMoves {
    package struct FollowMove {
        package let window: Window
        package let workspace: String
        package let space: UInt64
        package let from: String?
    }

    private enum Progress {
        case creating(String)
        case moving
        case following(FollowMove)
    }

    private var progress: [CGWindowID: Progress] = [:]
    private var membership: [CGWindowID: UInt64] = [:]
    private var arrivals: [CGWindowID: CGRect] = [:]

    package var isEmpty: Bool { progress.isEmpty }
    package var movingIDs: Set<CGWindowID> { Set(progress.keys.filter(isMoving)) }

    package func isMoving(_ id: CGWindowID) -> Bool {
        switch progress[id] {
        case .moving, .following: return true
        case .creating, nil: return false
        }
    }

    package func isBusy(_ id: CGWindowID) -> Bool { progress[id] != nil }

    package func requestedWorkspace(_ id: CGWindowID) -> String? {
        guard case .creating(let workspace) = progress[id] else { return nil }
        return workspace
    }

    package mutating func requestWorkspace(_ id: CGWindowID, workspace: String) { progress[id] = .creating(workspace) }

    package mutating func cancelRequest(_ id: CGWindowID) {
        if case .creating = progress[id] { progress[id] = nil }
    }

    package mutating func begin(_ id: CGWindowID) { progress[id] = .moving }

    package mutating func follow(_ move: FollowMove) { progress[move.window.id] = .following(move) }

    package func following(to workspace: String) -> [CGWindowID: FollowMove] {
        progress.compactMapValues {
            guard case .following(let move) = $0, move.workspace == workspace else { return nil }
            return move
        }
    }

    package mutating func finish(_ id: CGWindowID, on space: UInt64? = nil) {
        progress[id] = nil
        if let space { membership[id] = space }
    }

    package func confirms(_ id: CGWindowID, on space: UInt64) -> Bool { membership[id] == space }

    package mutating func observedMembership(_ id: CGWindowID, observed: Set<UInt64>) -> Set<UInt64> {
        guard let space = membership[id] else { return observed }
        if observed == [space] { membership[id] = nil }
        return [space]
    }

    package mutating func arrived(_ id: CGWindowID, frame: CGRect) { arrivals[id] = frame }

    package mutating func takeArrivals() -> [CGWindowID: CGRect] {
        defer { arrivals = [:] }
        return arrivals
    }

    package mutating func desktopBecameIdle() {
        progress = progress.filter { if case .following = $0.value { return false }; return true }
        arrivals = [:]
    }

    package mutating func forget(_ id: CGWindowID) {
        progress[id] = nil
        membership[id] = nil
        arrivals[id] = nil
    }
}
