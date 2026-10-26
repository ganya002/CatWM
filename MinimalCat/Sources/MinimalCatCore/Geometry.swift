import CoreGraphics

public enum Geometry {
    public static let gap: CGFloat = 8

    public static func frame(for place: Place, on display: Display) -> CGRect {
        let area = display.visible.insetBy(dx: gap, dy: gap)
        let halfWidth = (area.width - gap) / 2, halfHeight = (area.height - gap) / 2
        switch place {
        case .left: return CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        case .right: return CGRect(x: area.maxX - halfWidth, y: area.minY, width: halfWidth, height: area.height)
        case .top: return CGRect(x: area.minX, y: area.minY, width: area.width, height: halfHeight)
        case .bottom: return CGRect(x: area.minX, y: area.maxY - halfHeight, width: area.width, height: halfHeight)
        case .big:
            guard display.isUltrawide else { return area }
            let width = (area.width * 0.55).rounded()
            return CGRect(x: area.midX - width / 2, y: area.minY, width: width, height: area.height)
        }
    }

    /// The place a frame already sits in, so a second press on the same side can move on.
    public static func place(of frame: CGRect, on display: Display) -> Place? {
        Place.allCases.first { approxEqual(Self.frame(for: $0, on: display), frame) }
    }

    public static func display(containing frame: CGRect, in displays: [Display]) -> Display? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = displays.first(where: { $0.frame.contains(center) }) { return hit }
        return displays.max { overlap(frame, $0.frame) < overlap(frame, $1.frame) }
    }

    /// The display that touches `display` on that side, nearest to its vertical center.
    public static func neighbour(of display: Display, toward side: Side, in displays: [Display]) -> Display? {
        let candidates = displays.filter { other in
            other != display && (side == .left ? other.frame.midX < display.frame.midX
                                              : other.frame.midX > display.frame.midX)
        }
        return candidates.min {
            abs($0.frame.midX - display.frame.midX) + abs($0.frame.midY - display.frame.midY)
                < abs($1.frame.midX - display.frame.midX) + abs($1.frame.midY - display.frame.midY)
        }
    }

    /// The nearest window whose center lies on that side of `from`.
    public static func window(beside from: CGRect, toward side: Side, among windows: [WindowInfo]) -> WindowInfo? {
        let origin = CGPoint(x: from.midX, y: from.midY)
        return windows
            .filter { side == .left ? $0.frame.midX < origin.x - 1 : $0.frame.midX > origin.x + 1 }
            .min { distance($0.frame, origin) < distance($1.frame, origin) }
    }

    /// A frame as fractions of a display's visible area, so it survives a resolution change.
    public static func fraction(of frame: CGRect, in display: Display) -> CGRect {
        let area = display.visible
        return CGRect(x: (frame.minX - area.minX) / area.width, y: (frame.minY - area.minY) / area.height,
                      width: frame.width / area.width, height: frame.height / area.height)
    }

    public static func absolute(_ fraction: CGRect, in display: Display) -> CGRect {
        let area = display.visible
        return CGRect(x: area.minX + fraction.minX * area.width, y: area.minY + fraction.minY * area.height,
                      width: fraction.width * area.width, height: fraction.height * area.height).integral
    }

    public static func approxEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let cut = lhs.intersection(rhs)
        return cut.isNull ? 0 : cut.width * cut.height
    }

    private static func distance(_ frame: CGRect, _ point: CGPoint) -> CGFloat {
        let dx = frame.midX - point.x, dy = frame.midY - point.y
        return dx * dx + dy * dy
    }
}
