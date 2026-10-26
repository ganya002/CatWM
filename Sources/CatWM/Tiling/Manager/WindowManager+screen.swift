import AppKit

extension WindowManager {
    func screen(from source: Screen, spec: String, in screens: [Screen]) -> Screen? {
        if let dir = Direction(spec) {
            let center = source.center
            return screens.filter { other in
                switch dir {
                case .left: other.center.x < center.x - 1
                case .right: other.center.x > center.x + 1
                case .upward: other.center.y < center.y - 1
                case .down: other.center.y > center.y + 1
                }
            }.min {
                hypot($0.center.x - center.x, $0.center.y - center.y)
                    < hypot($1.center.x - center.x, $1.center.y - center.y)
            }
        }
        let i = screens.firstIndex { $0.uuid == source.uuid } ?? 0
        if spec.hasPrefix("+") || spec.hasPrefix("-"), let delta = Int(spec), !screens.isEmpty {
            return screens[((i + delta % screens.count) % screens.count + screens.count) % screens.count]
        }
        if let index = Int(spec), screens.indices.contains(index) { return screens[index] }
        return nil
    }
}

extension WindowManager {
    static let maxAnimatedMoves = 6

    var focusedScreen: NSScreen? { currentScreen()?.nsScreen }
}

final class ScreenState {
    var strip = Strip()
    var zoomed: CGWindowID?

    func copy() -> ScreenState {
        let clone = ScreenState()
        clone.strip = strip; clone.zoomed = zoomed
        return clone
    }
}
