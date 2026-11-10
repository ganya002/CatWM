import AppKit
import CatWMKit
import SwiftUI

final class TileView: NSView {
    private let card = CALayer()
    private let sheen = CAGradientLayer()
    private var dots: [CALayer] = []
    private let main: Bool

    private static let accent = Theme.iconAccent

    init(frame: NSRect, main: Bool) {
        self.main = main
        super.init(frame: frame)
        wantsLayer = true
        card.backgroundColor = main
            ? Self.accent.withAlphaComponent(0.92).cgColor
            : NSColor(white: 1, alpha: 0.13).cgColor
        card.borderColor = NSColor(white: 1, alpha: main ? 0.5 : 0.38).cgColor
        card.borderWidth = 1
        card.cornerRadius = 14
        card.cornerCurve = .continuous
        card.shadowColor = (main ? Self.accent : .black).cgColor
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
        for alpha in [0.55, 0.35, 0.25] {
            let dot = CALayer()
            dot.backgroundColor = NSColor(white: 1, alpha: main ? alpha + 0.25 : alpha).cgColor
            dot.cornerRadius = 4.5
            card.addSublayer(dot)
            dots.append(dot)
        }
        layer?.addSublayer(card)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let inner = bounds.insetBy(dx: Intro.margin, dy: Intro.margin)
        card.bounds = CGRect(origin: .zero, size: CGSize(width: max(0, inner.width), height: max(0, inner.height)))
        card.position = CGPoint(x: inner.midX, y: inner.midY)
        sheen.frame = card.bounds
        for (i, dot) in dots.enumerated() {
            dot.frame = CGRect(x: 12 + CGFloat(i) * 15, y: card.bounds.height - 11 - 9, width: 9, height: 9)
        }
        CATransaction.commit()
    }

    func squish() {
        Motion.squish(card)
    }

    func brace() {
        Motion.brace(card)
    }
}
