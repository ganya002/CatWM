import AppKit
import ApplicationServices

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
    var pixelAligned: CGRect {
        let x0 = minX.rounded(), y0 = minY.rounded(), x1 = maxX.rounded(), y1 = maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    func approxEqual(_ o: CGRect, tolerance t: CGFloat = 1.5) -> Bool {
        abs(minX - o.minX) <= t && abs(minY - o.minY) <= t && abs(width - o.width) <= t && abs(height - o.height) <= t
    }
}
