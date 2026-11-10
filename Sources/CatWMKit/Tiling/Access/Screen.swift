import AppKit
import ApplicationServices

package struct Screen {
    package let id: CGDirectDisplayID
    package let uuid: String
    package let frame: CGRect
    package let visible: CGRect
    package let isBuiltin: Bool
    package let nsScreen: NSScreen?

    package var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    package var name: String { nsScreen?.localizedName ?? uuid }

    package static func all() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        let screens = NSScreen.screens.compactMap { screen -> Screen? in
            guard let id = screen.displayID else { return nil }
            let uuid = screen.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: flip(screen.frame), visible: flip(screen.visibleFrame),
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, nsScreen: screen)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        return (Instance.scope ?? Instance.embedding.scope)?.filter(screens) ?? screens
    }
}

extension CGRect {
    package var center: CGPoint { CGPoint(x: midX, y: midY) }
    package var pixelAligned: CGRect {
        let left = minX.rounded(), top = minY.rounded(), right = maxX.rounded(), bottom = maxY.rounded()
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    package func approxEqual(_ other: CGRect, tolerance: CGFloat = 1.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

package func mouseLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
