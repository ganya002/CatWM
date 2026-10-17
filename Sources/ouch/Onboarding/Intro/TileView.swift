import AppKit
import SwiftUI

final class TileView: NSView {
    private let card = CALayer()
    private let sheen = CAGradientLayer()
    private var dots: [CALayer] = []
    private let main: Bool

    private static let blue = Theme.iconBlue

    init(frame: NSRect, main: Bool) {
        self.main = main
        super.init(frame: frame)
        wantsLayer = true
        card.backgroundColor = main ? Self.blue.withAlphaComponent(0.92).cgColor : NSColor(white: 1, alpha: 0.13).cgColor
        card.borderColor = NSColor(white: 1, alpha: main ? 0.5 : 0.38).cgColor
        card.borderWidth = 1
        card.cornerRadius = 14
        card.cornerCurve = .continuous
        card.shadowColor = (main ? Self.blue : .black).cgColor
        card.shadowOpacity = main ? 0.35 : 0.25
        card.shadowRadius = 24
        card.shadowOffset = CGSize(width: 0, height: -16)
        sheen.colors = [NSColor(white: 1, alpha: main ? 0.22 : 0.12).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.55)
        sheen.cornerRadius = 14
        sheen.cornerCurve = .continuous
        sheen.masksToBounds = true
        card.addSublayer(sheen)
        for a in [0.55, 0.35, 0.25] {
            let d = CALayer()
            d.backgroundColor = NSColor(white: 1, alpha: main ? a + 0.25 : a).cgColor
            d.cornerRadius = 4.5
            card.addSublayer(d)
            dots.append(d)
        }
        layer?.addSublayer(card)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = bounds.insetBy(dx: Intro.margin, dy: Intro.margin)
        card.bounds = CGRect(origin: .zero, size: CGSize(width: max(0, r.width), height: max(0, r.height)))
        card.position = CGPoint(x: r.midX, y: r.midY)
        sheen.frame = card.bounds
        for (i, d) in dots.enumerated() {
            d.frame = CGRect(x: 12 + CGFloat(i) * 15, y: card.bounds.height - 11 - 9, width: 9, height: 9)
        }
        CATransaction.commit()
    }

    func squish() {
        for (key, values) in [("transform.scale.x", [1, 1.035, 0.99, 1]), ("transform.scale.y", [1, 0.955, 1.01, 1])] {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = values
            a.keyTimes = [0, 0.3, 0.7, 1]
            a.duration = 0.42
            a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeOut)]
            card.add(a, forKey: key)
        }
    }

    func brace() {
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.92
        shrink.duration = 0.25
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        card.add(shrink, forKey: "brace")
        let glow = CABasicAnimation(keyPath: "shadowRadius")
        glow.toValue = 48
        glow.duration = 0.25
        glow.fillMode = .forwards
        glow.isRemovedOnCompletion = false
        card.add(glow, forKey: "glow")
    }
}
