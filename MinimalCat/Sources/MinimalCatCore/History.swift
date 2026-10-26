import CoreGraphics
import Foundation

public struct Move: Equatable, Sendable {
    public let window: WindowID
    public let start: CGRect
    public let end: CGRect
    public init(window: WindowID, start: CGRect, end: CGRect) {
        self.window = window; self.start = start; self.end = end
    }
    public var reversed: Move { Move(window: window, start: end, end: start) }
}

/// One thing that moved windows, so one undo puts all of it back.
public struct Step: Equatable, Sendable {
    public let label: String
    public let cause: Cause
    public let displays: DisplaySet
    public let moves: [Move]
    public init(label: String, cause: Cause, displays: DisplaySet, moves: [Move]) {
        self.label = label; self.cause = cause; self.displays = displays; self.moves = moves
    }
}

public struct History: Sendable {
    public static let depth = 30
    public private(set) var undoSteps: [Step] = []
    public private(set) var redoSteps: [Step] = []
    public init() {}

    public mutating func record(_ step: Step) {
        guard !step.moves.isEmpty else { return }
        undoSteps.append(step)
        if undoSteps.count > Self.depth { undoSteps.removeFirst(undoSteps.count - Self.depth) }
        redoSteps.removeAll()
    }

    public enum Pop: Equatable, Sendable {
        case step(Step)
        case empty
        /// The step was made on other monitors. It stays on the stack until they come back.
        case otherDisplays(Step)
    }

    public mutating func undo(on displays: DisplaySet) -> Pop {
        guard let step = undoSteps.last else { return .empty }
        guard step.displays == displays else { return .otherDisplays(step) }
        undoSteps.removeLast()
        redoSteps.append(step)
        return .step(Step(label: step.label, cause: step.cause, displays: step.displays,
                          moves: step.moves.map(\.reversed)))
    }

    public mutating func redo(on displays: DisplaySet) -> Pop {
        guard let step = redoSteps.last else { return .empty }
        guard step.displays == displays else { return .otherDisplays(step) }
        redoSteps.removeLast()
        undoSteps.append(step)
        return .step(step)
    }

    /// A window that closed can't be put back, so its moves leave every step.
    public mutating func forget(_ window: WindowID) {
        func strip(_ steps: [Step]) -> [Step] {
            steps.compactMap { step in
                let moves = step.moves.filter { $0.window != window }
                return moves.isEmpty ? nil : Step(label: step.label, cause: step.cause,
                                                   displays: step.displays, moves: moves)
            }
        }
        undoSteps = strip(undoSteps)
        redoSteps = strip(redoSteps)
    }
}
