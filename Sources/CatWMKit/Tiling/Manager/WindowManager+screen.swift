import AppKit

extension WindowManager {
    package func screen(from source: Screen, spec: String, in screens: [Screen]) -> Screen? {
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
    package static let maxAnimatedMoves = 6

    package var focusedScreen: NSScreen? { currentScreen()?.nsScreen }
}

package final class ScreenState {
    package var layout: Layout
    package var ratio: CGFloat = 0.5
    package var mainCount = 1
    package var zoomed: CGWindowID?
    var layouts: [Layout]?
    var layoutBeforeRule: Layout?
    package var dwindle = DwindleTree()
    package init(layout: Layout) { self.layout = layout }

    package func copy() -> ScreenState {
        let clone = ScreenState(layout: layout)
        clone.ratio = ratio; clone.mainCount = mainCount; clone.zoomed = zoomed
        clone.layouts = layouts; clone.layoutBeforeRule = layoutBeforeRule; clone.dwindle = dwindle
        return clone
    }
}
