import CoreGraphics

package struct FollowedMoves {
    private var moves: [CGWindowID: Animator.Move] = [:]
    private var refusals: [CGWindowID: CGSize] = [:]

    package subscript(id: CGWindowID) -> Animator.Move? { moves[id] }

    package mutating func add(_ move: Animator.Move) { moves[move.window.id] = move }

    package mutating func remove(_ id: CGWindowID) {
        moves[id] = nil
        refusals[id] = nil
    }

    package mutating func removeAll() -> [Animator.Move] {
        defer { moves = [:]; refusals = [:] }
        return Array(moves.values)
    }

    package mutating func minimum(after move: Animator.Move, actual: CGSize?) -> CGSize? {
        let id = move.window.id, target = move.target.size
        guard moves[id] != nil, let actual else { return nil }
        let wider = actual.width > target.width + 1, taller = actual.height > target.height + 1
        guard wider || taller else { refusals[id] = nil; return nil }
        defer { refusals[id] = actual }
        guard let previous = refusals[id], abs(previous.width - actual.width) <= 1,
              abs(previous.height - actual.height) <= 1 else { return nil }
        return CGSize(width: wider ? actual.width : 0, height: taller ? actual.height : 0)
    }
}
