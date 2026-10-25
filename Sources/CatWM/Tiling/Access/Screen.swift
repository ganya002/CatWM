import AppKit
import ApplicationServices

struct Screen {
    let id: CGDirectDisplayID
    let uuid: String
    let frame: CGRect
    let visible: CGRect
    let isBuiltin: Bool
    let nsScreen: NSScreen

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    static func all() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.displayID else { return nil }
            let uuid = screen.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: flip(screen.frame), visible: flip(screen.visibleFrame),
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, nsScreen: screen)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}
