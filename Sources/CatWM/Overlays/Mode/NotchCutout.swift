import AppKit
import SwiftUI

struct NotchCutout: Shape {
    let halfWidth: CGFloat
    let height: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
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
