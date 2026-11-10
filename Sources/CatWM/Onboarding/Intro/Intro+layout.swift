import AppKit
import CatWMKit
import SwiftUI

extension Intro {
    func layout(bsp: Bool, _ count: Int = Intro.count) -> [NSRect] {
        let area = screen.frame.insetBy(dx: 28, dy: 28)
        let gap: CGFloat = 18
        var out: [NSRect] = []
        var rest = CGRect(x: 0, y: 0, width: area.width + gap, height: area.height + gap)
        if bsp || count == 1 {
            for i in 0..<(count - 1) {
                if i.isMultiple(of: 2) {
                    out.append(CGRect(x: rest.minX, y: rest.minY, width: rest.width / 2, height: rest.height))
                    rest = CGRect(x: rest.minX + rest.width / 2, y: rest.minY,
                                  width: rest.width / 2, height: rest.height)
                } else {
                    out.append(CGRect(x: rest.minX, y: rest.minY, width: rest.width, height: rest.height / 2))
                    rest = CGRect(x: rest.minX, y: rest.minY + rest.height / 2,
                                  width: rest.width, height: rest.height / 2)
                }
            }
            out.append(rest)
        } else {
            let main = rest.width / 2, height = rest.height / CGFloat(count - 1)
            out.append(CGRect(x: 0, y: 0, width: main, height: rest.height))
            for i in 0..<(count - 1) {
                out.append(CGRect(x: main, y: CGFloat(i) * height, width: rest.width - main, height: height))
            }
        }
        return out.map { slot in
            let inset = slot.insetBy(dx: gap / 2, dy: gap / 2)
            return NSRect(x: area.minX + inset.minX, y: area.maxY - inset.maxY,
                          width: inset.width, height: inset.height).integral
        }
    }

    func fadeIn() {
        Motion.group(0.8, curve: CAMediaTimingFunction(name: .easeOut)) {
            Motion.setAlpha(1, on: dim)
            Motion.setAlpha(1, on: skipLabel)
        }
    }

    func arrive(_ count: Int) {
        let frames = layout(bsp: true, count)
        for i in 0..<(count - 1) {
            move(i, to: frames[i], alpha: 1, duration: 0.45)
            later(0.12) { [weak self] in self?.tile(i)?.squish() }
        }
        let i = count - 1, slot = frames[i]
        tiles[i].setFrame(padded(slot.insetBy(dx: slot.width * 0.3, dy: slot.height * 0.3)), display: false)
        move(i, to: slot, alpha: 1, duration: 0.45)
        later(0.12) { [weak self] in self?.tile(i)?.squish() }
    }

    func showWord() {
        for i in tiles.indices { Motion.group(0.5) { Motion.setAlpha(i == 0 ? 0.4 : 0.3, on: tiles[i]) } }
        wordModel.landed = true
        Motion.group(1.1) {
            Motion.setAlpha(1, on: word)
            Motion.setFrame(wordFrame, on: word)
        }
    }

    func hideWord() {
        Motion.group(0.5, curve: CAMediaTimingFunction(name: .easeOut)) {
            Motion.setAlpha(0, on: word)
            Motion.setAlpha(0, on: skipLabel)
        }
    }

    func retile() {
        wordModel.subtitle = true
        let step = IntroScore.Beat.step
        for (i, slot) in layout(bsp: false).enumerated() {
            move(i, to: slot, alpha: i == 0 ? 0.4 : 0.3, duration: 0.6, delay: Double(i) * step)
            later(Double(i) * step + 0.1) { [weak self] in self?.tile(i)?.squish() }
        }
    }

    func gather() {
        hideWord()
        let span = IntroScore.Beat.impact - 0.25 - IntroScore.Beat.gather
        let center = NSPoint(x: landing.midX, y: landing.midY)
        let width = landing.width * 0.42, height = landing.height * 0.42
        let pull = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.2, 1)
        for i in tiles.indices.reversed() {
            let offset = CGFloat(i) * 7
            let rect = NSRect(x: center.x - width / 2 + offset, y: center.y - height / 2 - offset,
                              width: width, height: height)
            move(i, to: rect, alpha: i == 0 ? 1 : 0.85, duration: span,
                 delay: Double(Self.count - 1 - i) * 0.04, curve: pull)
            tiles[i].order(.above, relativeTo: i == Self.count - 1 ? 0 : tiles[i + 1].windowNumber)
        }
        later(span) { [weak self] in self?.tiles.indices.forEach { self?.tile($0)?.brace() } }
    }

    func impact() {
        guard !done else { return }
        pending.forEach { $0.cancel() }
        pending = []
        let origin = NSPoint(x: landing.midX - screen.frame.minX, y: landing.midY - screen.frame.minY)
        (effects.contentView as? ImpactView)?.fire(at: origin)
        let burst = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.2, 1)
        for i in tiles.indices {
            let spread = CGFloat(i) * 10
            move(i, to: landing.insetBy(dx: -spread, dy: -spread), alpha: 0, duration: 0.6, curve: burst)
        }
        finish(over: 1.1)
    }
}
