import CoreGraphics

struct NativeWindowMoves {
    struct FollowMove {
        let window: Window
        let workspace: String
        let space: UInt64
        let from: String?
    }

    private enum Progress {
        case creating(String)
        case moving
        case following(FollowMove)
    }

    private var progress: [CGWindowID: Progress] = [:]
    private var membership: [CGWindowID: UInt64] = [:]
    private var arrivals: [CGWindowID: CGRect] = [:]

    var isEmpty: Bool { progress.isEmpty }
    var movingIDs: Set<CGWindowID> { Set(progress.keys.filter(isMoving)) }

    func isMoving(_ id: CGWindowID) -> Bool {
        switch progress[id] {
        case .moving, .following: return true
        case .creating, nil: return false
        }
    }

    func isBusy(_ id: CGWindowID) -> Bool { progress[id] != nil }

    func requestedWorkspace(_ id: CGWindowID) -> String? {
        guard case .creating(let workspace) = progress[id] else { return nil }
        return workspace
    }

    mutating func requestWorkspace(_ id: CGWindowID, workspace: String) { progress[id] = .creating(workspace) }

    mutating func cancelRequest(_ id: CGWindowID) {
        if case .creating = progress[id] { progress[id] = nil }
    }

    mutating func begin(_ id: CGWindowID) { progress[id] = .moving }

    mutating func follow(_ move: FollowMove) { progress[move.window.id] = .following(move) }

    func following(to workspace: String) -> [CGWindowID: FollowMove] {
        progress.compactMapValues {
            guard case .following(let move) = $0, move.workspace == workspace else { return nil }
            return move
        }
    }

    mutating func finish(_ id: CGWindowID, on space: UInt64? = nil) {
        progress[id] = nil
        if let space { membership[id] = space }
    }

    func confirms(_ id: CGWindowID, on space: UInt64) -> Bool { membership[id] == space }

    mutating func observedMembership(_ id: CGWindowID, observed: Set<UInt64>) -> Set<UInt64> {
        guard let space = membership[id] else { return observed }
        if observed == [space] { membership[id] = nil }
        return [space]
    }

    mutating func arrived(_ id: CGWindowID, frame: CGRect) { arrivals[id] = frame }

    mutating func takeArrivals() -> [CGWindowID: CGRect] {
        defer { arrivals = [:] }
        return arrivals
    }

    mutating func desktopBecameIdle() {
        progress = progress.filter { if case .following = $0.value { return false }; return true }
        arrivals = [:]
    }

    mutating func forget(_ id: CGWindowID) {
        progress[id] = nil
        membership[id] = nil
        arrivals[id] = nil
    }
}
