import AppKit
import ApplicationServices

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
    var pixelAligned: CGRect {
        let left = minX.rounded(), top = minY.rounded(), right = maxX.rounded(), bottom = maxY.rounded()
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }
    func approxEqual(_ other: CGRect, tolerance: CGFloat = 1.5) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
