import AppKit
import SwiftUI

struct OutlineHalf: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1), rad = max(0, radius - 1)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
