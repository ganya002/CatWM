import AppKit

enum Direction {
    case left, right, up, down
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
