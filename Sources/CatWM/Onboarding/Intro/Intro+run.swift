import AppKit
import CatWMKit
import SwiftUI

extension Intro {
    func run() {
        dim.orderFrontRegardless()
        tiles.forEach { $0.orderFrontRegardless() }
        word.orderFrontRegardless()
        effects.orderFrontRegardless()
        score.play()
        let beat = IntroScore.Beat.self
        fadeIn()
        for (i, time) in beat.arrive.enumerated() { later(time - 0.12) { [weak self] in self?.arrive(i + 1) } }
        later(beat.word - 0.25) { [weak self] in self?.showWord() }
        later(beat.retile - 0.1) { [weak self] in self?.retile() }
        later(beat.gather) { [weak self] in self?.gather() }
        later(beat.impact - 0.06) { [weak self] in self?.impact() }
    }

    func later(_ seconds: Double, _ block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        pending.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func skip() {
        guard !done else { return }
        pending.forEach { $0.cancel() }
        pending = []
        score.fadeOut()
        fadeIn()
        for i in tiles.indices { move(i, to: landing, alpha: 0, duration: 0.7, delay: Double(i) * 0.03) }
        hideWord()
        later(0.5) { [weak self] in self?.finish(over: 0.7) }
    }

    func finish(over seconds: Double) {
        guard !done else { return }
        done = true
        onDone()
        let panels = [dim, word] + tiles
        Motion.group(seconds, curve: CAMediaTimingFunction(name: .easeOut),
                changes: { panels.forEach { Motion.setAlpha(0, on: $0) } },
                completion: { panels.forEach { $0.orderOut(nil) } })
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [effects] in effects.orderOut(nil) }
    }

    func build() {
        let frame = screen.frame
        let root = ClickView(frame: NSRect(origin: .zero, size: frame.size))
        root.onClick = { [weak self] in self?.skip() }
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        root.addSubview(blur)
        let shade = CAGradientLayer()
        shade.type = .radial
        shade.colors = [Intro.graphite.withAlphaComponent(0.3).cgColor,
                        Intro.graphite.withAlphaComponent(0.62).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.5)
        shade.endPoint = CGPoint(x: 1.1, y: 1.1)
        let shadeView = NSView(frame: root.bounds)
        shadeView.autoresizingMask = [.width, .height]
        shadeView.wantsLayer = true
        shade.frame = shadeView.bounds
        shade.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        shadeView.layer?.addSublayer(shade)
        root.addSubview(shadeView)
        skipLabel.font = Theme.nsBody(12)
        skipLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        skipLabel.sizeToFit()
        skipLabel.setFrameOrigin(NSPoint(x: frame.width - skipLabel.frame.width - 20, y: 18))
        skipLabel.alphaValue = 0
        root.addSubview(skipLabel)
        dim.contentView = root
        dim.alphaValue = 0

        let center = NSRect(x: frame.midX, y: frame.midY, width: 0, height: 0)
        for i in 0..<Self.count {
            let panel = CatWMPanel(role: .overlay(.above(.statusBar, 2), clickThrough: true), frame: padded(center))
            panel.contentView = TileView(frame: NSRect(origin: .zero, size: panel.frame.size), main: i == 0)
            panel.alphaValue = 0
            tiles.append(panel)
        }

        let size = max(64, min(140, frame.width * 0.11))
        word.contentView = NSHostingView(rootView: WordmarkView(model: wordModel, size: size))
        word.alphaValue = 0

        effects.contentView = ImpactView(frame: NSRect(origin: .zero, size: frame.size))
    }

    func tile(_ i: Int) -> TileView? { tiles.indices.contains(i) ? tiles[i].contentView as? TileView : nil }

    func padded(_ rect: NSRect) -> NSRect { rect.insetBy(dx: -Self.margin, dy: -Self.margin) }

    func move(_ i: Int, to rect: NSRect, alpha: CGFloat, duration: Double, delay: Double = 0,
              curve: CAMediaTimingFunction? = nil) {
        let panel = tiles[i], timing = curve ?? self.curve
        let run = {
            Motion.group(duration, curve: timing) { Motion.setFrame(self.padded(rect), on: panel) }
            Motion.group(min(duration, 0.4), curve: CAMediaTimingFunction(name: .easeOut)) {
                Motion.setAlpha(alpha, on: panel)
            }
        }
        if delay > 0 { later(delay, run) } else { run() }
    }
}
