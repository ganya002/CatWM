import AppKit

enum Direction: String, CaseIterable {
    case left = "l", right = "r", up = "u", down = "d"

    var title: String { String(describing: self).capitalized }
    var symbolName: String { String(describing: self) }

    static let hintArrows = Dictionary(uniqueKeysWithValues: allCases.flatMap { direction in
        let arrow: String
        switch direction {
        case .left: arrow = "←"
        case .right: arrow = "→"
        case .up: arrow = "↑"
        case .down: arrow = "↓"
        }
        return [(direction.rawValue, arrow), (direction.symbolName, arrow)]
    })
    init?(_ s: String) {
        switch s.lowercased() {
        case "l", "left": self = .left
        case "r", "right": self = .right
        case "u", "up", "t", "top": self = .up
        case "d", "down", "b", "bottom": self = .down
        default: return nil
        }
    }
}
