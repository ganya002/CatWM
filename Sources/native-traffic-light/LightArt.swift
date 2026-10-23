import CoreGraphics

struct ArtStop: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

struct LightArt: Equatable {
    var fill: [ArtStop]
    var ring: [ArtStop]
    var glow: [ArtStop]
    var glowCenterY: Double
    var glowRadius: Double
    var glowSquash: Double
    var halo: [ArtStop]
    var haloExtent: Double
    var haloOffsetY: Double
    var ringWidth: Double
    var fillInset: Double

    func draw(in ctx: CGContext, center: CGPoint, diameter: CGFloat) {
        let radius = diameter / 2
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: diameter, height: diameter)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        ctx.saveGState()
        defer { ctx.restoreGState() }

        if let gradient = gradient(halo, space), halo.contains(where: { $0.alpha > 0.0005 }) {
            ctx.saveGState()
            let outside = CGMutablePath()
            outside.addRect(disc.insetBy(dx: -diameter, dy: -diameter))
            outside.addEllipse(in: disc)
            ctx.addPath(outside)
            ctx.clip(using: .evenOdd)
            let origin = CGPoint(x: center.x, y: center.y + haloOffsetY)
            ctx.drawRadialGradient(gradient, startCenter: origin, startRadius: radius - 1, endCenter: origin,
                                   endRadius: radius + haloExtent, options: [])
            ctx.restoreGState()
        }

        func vertical(_ stops: [ArtStop]) -> CGGradient? { gradient(stops, space) }
        func paint(_ gradient: CGGradient?) {
            guard let gradient else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: disc.minY), end: CGPoint(x: 0, y: disc.maxY),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        ctx.saveGState()
        ctx.addEllipse(in: disc.insetBy(dx: fillInset, dy: fillInset))
        ctx.clip()
        paint(vertical(fill))
        if let gradient = vertical(glow), glow.contains(where: { $0.alpha > 0.0005 }) {
            ctx.translateBy(x: center.x, y: disc.minY + glowCenterY * diameter)
            ctx.scaleBy(x: 1, y: glowSquash)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                   endRadius: glowRadius * diameter, options: [])
        }
        ctx.restoreGState()

        ctx.saveGState()
        let width = ringWidth * diameter
        let annulus = CGMutablePath()
        annulus.addEllipse(in: disc)
        annulus.addEllipse(in: disc.insetBy(dx: width, dy: width))
        ctx.addPath(annulus)
        ctx.clip(using: .evenOdd)
        paint(vertical(ring))
        ctx.restoreGState()
    }

    private func gradient(_ stops: [ArtStop], _ space: CGColorSpace) -> CGGradient? {
        guard stops.count > 1 else { return nil }
        let locations = (0..<stops.count).map { CGFloat($0) / CGFloat(stops.count - 1) }
        return CGGradient(colorsSpace: space, colors: stops.map(\.cgColor) as CFArray, locations: locations)
    }
}
