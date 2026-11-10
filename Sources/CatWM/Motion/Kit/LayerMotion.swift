import AppKit
import CatWMKit

extension Motion {
    static func impact(on root: CALayer, center: NSPoint, bounds: NSRect) {
        let flash = CALayer()
        flash.frame = bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 0.22, 0]
        blink.keyTimes = [0, 0.08, 1]
        blink.duration = 0.7
        blink.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeOut)]
        flash.add(blink, forKey: "blink")

        let reach = hypot(max(center.x, bounds.width - center.x), max(center.y, bounds.height - center.y)) * 1.1
        for (i, (color, width)) in [(NSColor.white, 3.0), (Theme.iconAccent, 10.0)].enumerated() {
            let ring = CAShapeLayer()
            let circle = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
            ring.path = CGPath(ellipseIn: circle, transform: nil)
            ring.position = center
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = width
            ring.opacity = 0
            ring.shadowColor = color.cgColor
            ring.shadowRadius = 18
            ring.shadowOpacity = 0.9
            root.addSublayer(ring)
            let delay = Double(i) * 0.08
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.04
            grow.toValue = 1
            grow.duration = 1.2
            grow.beginTime = CACurrentMediaTime() + delay
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.7, 0.3, 1)
            grow.fillMode = .both
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.95, 0]
            fade.keyTimes = [0, 0.05, 1]
            fade.duration = 1.2
            fade.beginTime = grow.beginTime
            fade.fillMode = .both
            ring.add(grow, forKey: "grow")
            ring.add(fade, forKey: "fade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { root.sublayers?.forEach { $0.removeFromSuperlayer() } }
    }

    static func squish(_ layer: CALayer) {
        for (key, values) in [("transform.scale.x", [1, 1.035, 0.99, 1]), ("transform.scale.y", [1, 0.955, 1.01, 1])] {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = [0, 0.3, 0.7, 1]
            animation.duration = 0.42
            animation.timingFunctions = [CAMediaTimingFunction(name: .easeOut),
                                         CAMediaTimingFunction(name: .easeInEaseOut),
                                         CAMediaTimingFunction(name: .easeOut)]
            layer.add(animation, forKey: key)
        }
    }

    static func brace(_ layer: CALayer) {
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.92
        shrink.duration = 0.25
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        layer.add(shrink, forKey: "brace")
        let glow = CABasicAnimation(keyPath: "shadowRadius")
        glow.toValue = 48
        glow.duration = 0.25
        glow.fillMode = .forwards
        glow.isRemovedOnCompletion = false
        layer.add(glow, forKey: "glow")
    }
}
