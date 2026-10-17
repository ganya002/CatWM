import AppKit
import SwiftUI

extension Intro {
    func layout(bsp: Bool, _ n: Int = Intro.count) -> [NSRect] {
        let f = screen.frame.insetBy(dx: 28, dy: 28)
        let gap: CGFloat = 18
        var out: [NSRect] = []
        var r = CGRect(x: 0, y: 0, width: f.width + gap, height: f.height + gap)
        if bsp || n == 1 {
            for i in 0..<(n - 1) {
                if i % 2 == 0 {
                    out.append(CGRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height))
                    r = CGRect(x: r.minX + r.width / 2, y: r.minY, width: r.width / 2, height: r.height)
                } else {
                    out.append(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2))
                    r = CGRect(x: r.minX, y: r.minY + r.height / 2, width: r.width, height: r.height / 2)
                }
            }
            out.append(r)
        } else {
            let main = r.width / 2, h = r.height / CGFloat(n - 1)
            out.append(CGRect(x: 0, y: 0, width: main, height: r.height))
            for i in 0..<(n - 1) { out.append(CGRect(x: main, y: CGFloat(i) * h, width: r.width - main, height: h)) }
        }
        return out.map { t in
            let g = t.insetBy(dx: gap / 2, dy: gap / 2)
            return NSRect(x: f.minX + g.minX, y: f.maxY - g.maxY, width: g.width, height: g.height).integral
        }
    }

    func fadeIn() {
        animate(0.8, curve: CAMediaTimingFunction(name: .easeOut)) {
            dim.animator().alphaValue = 1
            skipLabel.animator().alphaValue = 1
        }
    }

    func arrive(_ n: Int) {
        let frames = layout(bsp: true, n)
        for i in 0..<(n - 1) {
            move(i, to: frames[i], alpha: 1, duration: 0.45)
            later(0.12) { [weak self] in self?.tile(i)?.squish() }
        }
        let i = n - 1, slot = frames[i]
        tiles[i].setFrame(padded(slot.insetBy(dx: slot.width * 0.3, dy: slot.height * 0.3)), display: false)
        move(i, to: slot, alpha: 1, duration: 0.45)
        later(0.12) { [weak self] in self?.tile(i)?.squish() }
    }

    func showWord() {
        for i in tiles.indices { animate(0.5) { tiles[i].animator().alphaValue = i == 0 ? 0.4 : 0.3 } }
        wordModel.landed = true
        animate(1.1) {
            word.animator().alphaValue = 1
            word.animator().setFrame(wordFrame, display: true)
        }
    }

    func hideWord() {
        animate(0.5, curve: CAMediaTimingFunction(name: .easeOut)) {
            word.animator().alphaValue = 0
            skipLabel.animator().alphaValue = 0
        }
    }

    func retile() {
        wordModel.subtitle = true
        let step = IntroScore.Beat.step
        for (i, r) in layout(bsp: false).enumerated() {
            move(i, to: r, alpha: i == 0 ? 0.4 : 0.3, duration: 0.6, delay: Double(i) * step)
            later(Double(i) * step + 0.1) { [weak self] in self?.tile(i)?.squish() }
        }
    }

    func gather() {
        hideWord()
        let span = IntroScore.Beat.impact - 0.25 - IntroScore.Beat.gather
        let c = NSPoint(x: landing.midX, y: landing.midY)
        let w = landing.width * 0.42, h = landing.height * 0.42
        let pull = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.2, 1)
        for i in tiles.indices.reversed() {
            let o = CGFloat(i) * 7
            let r = NSRect(x: c.x - w / 2 + o, y: c.y - h / 2 - o, width: w, height: h)
            move(i, to: r, alpha: i == 0 ? 1 : 0.85, duration: span, delay: Double(Self.count - 1 - i) * 0.04, curve: pull)
            tiles[i].order(.above, relativeTo: i == Self.count - 1 ? 0 : tiles[i + 1].windowNumber)
        }
        later(span) { [weak self] in self?.tiles.indices.forEach { self?.tile($0)?.brace() } }
    }

    func impact() {
        guard !done else { return }
        pending.forEach { $0.cancel() }
        pending = []
        (fx.contentView as? ImpactView)?.fire(at: NSPoint(x: landing.midX - screen.frame.minX, y: landing.midY - screen.frame.minY))
        let burst = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.2, 1)
        for i in tiles.indices {
            let spread = CGFloat(i) * 10
            move(i, to: landing.insetBy(dx: -spread, dy: -spread), alpha: 0, duration: 0.6, curve: burst)
        }
        finish(over: 1.1)
    }
}
