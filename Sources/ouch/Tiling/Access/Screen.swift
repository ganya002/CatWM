import AppKit
import ApplicationServices

struct Screen {
    let id: CGDirectDisplayID
    let uuid: String
    let frame: CGRect
    let visible: CGRect
    let isBuiltin: Bool
    let ns: NSScreen

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    static func all() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let h = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        return NSScreen.screens.compactMap { s in
            guard let id = s.displayID else { return nil }
            let uuid = s.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: flip(s.frame), visible: flip(s.visibleFrame),
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, ns: s)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}
