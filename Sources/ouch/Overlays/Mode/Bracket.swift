import AppKit
import SwiftUI

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
