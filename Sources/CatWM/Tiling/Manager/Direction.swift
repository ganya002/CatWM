import AppKit

enum Direction: String, CaseIterable {
    case left = "l", right = "r", upward = "u", down = "d"

    var title: String { symbolName.capitalized }
    var symbolName: String {
        switch self {
        case .left: "left"
        case .right: "right"
        case .upward: "up"
        case .down: "down"
        }
    }

    static let hintArrows = Dictionary(uniqueKeysWithValues: allCases.flatMap { direction in
        let arrow: String
        switch direction {
        case .left: arrow = "←"
        case .right: arrow = "→"
        case .upward: arrow = "↑"
        case .down: arrow = "↓"
        }
        return [(direction.rawValue, arrow), (direction.symbolName, arrow)]
    })
    init?(_ text: String) {
        switch text.lowercased() {
        case "l", "left": self = .left
        case "r", "right": self = .right
        case "u", "up", "t", "top": self = .upward
        case "d", "down", "b", "bottom": self = .down
        default: return nil
        }
    }
}
