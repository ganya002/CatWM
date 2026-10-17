import AppKit

extension WindowManager {
    func screen(from s: Screen, spec: String, in screens: [Screen]) -> Screen? {
        if let dir = Direction(spec) {
            let c = s.center
            return screens.filter { o in
                switch dir {
                case .left: o.center.x < c.x - 1
                case .right: o.center.x > c.x + 1
                case .up: o.center.y < c.y - 1
                case .down: o.center.y > c.y + 1
                }
            }.min { hypot($0.center.x - c.x, $0.center.y - c.y) < hypot($1.center.x - c.x, $1.center.y - c.y) }
        }
        let i = screens.firstIndex { $0.uuid == s.uuid } ?? 0
        if spec.hasPrefix("+") || spec.hasPrefix("-"), let d = Int(spec) {
            return screens[((i + d) % screens.count + screens.count) % screens.count]
        }
        if let n = Int(spec), screens.indices.contains(n) { return screens[n] }
        return nil
    }
}
