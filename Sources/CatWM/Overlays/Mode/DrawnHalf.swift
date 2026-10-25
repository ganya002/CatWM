import AppKit
import SwiftUI

struct DrawnHalf: Shape {
    let radius: CGFloat
    let inset: CGFloat
    var notchHalfWidth: CGFloat = 0
    var notchHeight: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: inset, dy: inset)
        let rad = max(0, radius - inset)
        var path = Path()
        if notchHalfWidth > 0 {
            let x = box.midX + notchHalfWidth + inset, y = rect.minY + notchHeight + inset
            path.move(to: CGPoint(x: box.midX, y: y))
            path.addArc(tangent1End: CGPoint(x: x, y: y), tangent2End: CGPoint(x: x, y: box.minY),
                        radius: Notch.bottomRadius + inset)
            path.addArc(tangent1End: CGPoint(x: x, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.minY),
                        radius: max(0.5, Notch.flareRadius - inset))
        } else {
            path.move(to: CGPoint(x: box.midX, y: box.minY))
        }
        path.addArc(tangent1End: CGPoint(x: box.maxX, y: box.minY), tangent2End: CGPoint(x: box.maxX, y: box.maxY),
                    radius: rad)
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.midX, y: box.maxY))
        return path
    }
}
