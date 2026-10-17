import AppKit
import SwiftUI

struct DrawnHalf: Shape {
    let radius: CGFloat
    let inset: CGFloat
    var notchHalfWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let rad = max(0, radius - inset)
        var p = Path()
        if notchHalfWidth > 0 {
            let x = r.midX + notchHalfWidth + inset, y = rect.minY + notchHeight + inset
            p.move(to: CGPoint(x: r.midX, y: y))
            p.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: r.minY), radius: Notch.bottomRadius + inset)
            p.addArc(tangent1End: CGPoint(x: x, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: max(0.5, Notch.flareRadius - inset))
        } else {
            p.move(to: CGPoint(x: r.midX, y: r.minY))
        }
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}
