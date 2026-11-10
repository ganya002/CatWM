import AppKit
import CatWMKit
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

enum Notch {
    static let bottomRadius: CGFloat = 8
    static let flareRadius: CGFloat = 6
}

struct NotchCutout: Shape {
    let halfWidth: CGFloat
    let height: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(NotchFill(halfWidth: halfWidth, height: height).path(in: rect))
        return path
    }
}

struct NotchFill: Shape {
    let halfWidth: CGFloat
    let height: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard halfWidth > 0 else { return path }
        let left = rect.midX - halfWidth, right = rect.midX + halfWidth, top = rect.minY
        let bottom = Notch.bottomRadius, flare = Notch.flareRadius, kappa: CGFloat = 0.5523
        path.move(to: CGPoint(x: left - flare, y: top))
        path.addCurve(to: CGPoint(x: left, y: top + flare),
                      control1: CGPoint(x: left - flare + kappa * flare, y: top),
                      control2: CGPoint(x: left, y: top + flare - kappa * flare))
        path.addArc(tangent1End: CGPoint(x: left, y: top + height),
                    tangent2End: CGPoint(x: right, y: top + height), radius: bottom)
        path.addArc(tangent1End: CGPoint(x: right, y: top + height),
                    tangent2End: CGPoint(x: right, y: top), radius: bottom)
        path.addLine(to: CGPoint(x: right, y: top + flare))
        path.addCurve(to: CGPoint(x: right + flare, y: top),
                      control1: CGPoint(x: right, y: top + flare - kappa * flare),
                      control2: CGPoint(x: right + flare - kappa * flare, y: top))
        path.closeSubpath()
        return path
    }
}

struct Bracket: Shape {
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY),
                    radius: radius)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
