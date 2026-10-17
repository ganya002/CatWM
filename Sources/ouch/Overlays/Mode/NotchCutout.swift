import AppKit
import SwiftUI

struct NotchCutout: Shape {
    let halfWidth: CGFloat
    let height: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        guard halfWidth > 0 else { return p }
        let l = rect.midX - halfWidth, r = rect.midX + halfWidth, top = rect.minY
        let rb = Notch.bottomRadius, rf = Notch.flareRadius, k: CGFloat = 0.5523
        p.move(to: CGPoint(x: l - rf, y: top))
        p.addCurve(to: CGPoint(x: l, y: top + rf), control1: CGPoint(x: l - rf + k * rf, y: top), control2: CGPoint(x: l, y: top + rf - k * rf))
        p.addArc(tangent1End: CGPoint(x: l, y: top + height), tangent2End: CGPoint(x: r, y: top + height), radius: rb)
        p.addArc(tangent1End: CGPoint(x: r, y: top + height), tangent2End: CGPoint(x: r, y: top), radius: rb)
        p.addLine(to: CGPoint(x: r, y: top + rf))
        p.addCurve(to: CGPoint(x: r + rf, y: top), control1: CGPoint(x: r, y: top + rf - k * rf), control2: CGPoint(x: r + rf - k * rf, y: top))
        p.closeSubpath()
        return p
    }
}
