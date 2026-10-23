import CoreGraphics

enum GlyphKind: Equatable {
    case close
    case minimize
    case zoomPlus
    case zoomArrows
}

struct GlyphShape: Equatable {
    var length: Double
    var width: Double
    var radius: Double
    var dx: Double
    var dy: Double

    func path(_ kind: GlyphKind) -> CGPath {
        let path = CGMutablePath()
        func bar(angle: CGFloat) {
            let rect = CGRect(x: -length / 2, y: -width / 2, width: length, height: width)
            let bar = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
            path.addPath(bar, transform: CGAffineTransform(rotationAngle: angle))
        }
        switch kind {
        case .close:
            bar(angle: .pi / 4)
            bar(angle: -.pi / 4)
        case .minimize:
            bar(angle: 0)
        case .zoomPlus:
            bar(angle: 0)
            bar(angle: .pi / 2)
        case .zoomArrows:
            let inset = width / 2
            let offset = radius - inset
            let leg = length - width * 1.5
            func triangle(_ sign: CGFloat) {
                let corner = CGPoint(x: sign * offset, y: sign * offset)
                path.addLines(between: [
                    corner,
                    CGPoint(x: corner.x - sign * leg, y: corner.y),
                    CGPoint(x: corner.x, y: corner.y - sign * leg)
                ])
                path.closeSubpath()
            }
            triangle(-1)
            triangle(1)
        }
        return path
    }

    func draw(_ kind: GlyphKind, color: ArtStop, in ctx: CGContext, center: CGPoint) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.translateBy(x: center.x + dx, y: center.y + dy)
        ctx.setAlpha(color.alpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        let opaque = CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
        ctx.setFillColor(opaque)
        ctx.addPath(path(kind))
        if kind == .zoomArrows {
            ctx.setStrokeColor(opaque)
            ctx.setLineWidth(width)
            ctx.setLineJoin(.round)
            ctx.drawPath(using: .fillStroke)
        } else {
            ctx.fillPath()
        }
        ctx.endTransparencyLayer()
    }
}
