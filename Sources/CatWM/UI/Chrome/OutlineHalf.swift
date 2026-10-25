import AppKit
import SwiftUI

struct OutlineHalf: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: 1, dy: 1), rad = max(0, radius - 1)
        var path = Path()
        path.move(to: CGPoint(x: inner.midX, y: inner.minY))
        path.addArc(tangent1End: CGPoint(x: inner.maxX, y: inner.minY),
                    tangent2End: CGPoint(x: inner.maxX, y: inner.maxY), radius: rad)
        path.addArc(tangent1End: CGPoint(x: inner.maxX, y: inner.maxY),
                    tangent2End: CGPoint(x: inner.minX, y: inner.maxY), radius: rad)
        path.addLine(to: CGPoint(x: inner.midX, y: inner.maxY))
        return path
    }
}
