import AppKit
import SwiftUI

extension Intro {
    func run() {
        dim.orderFrontRegardless()
        tiles.forEach { $0.orderFrontRegardless() }
        word.orderFrontRegardless()
        fx.orderFrontRegardless()
        score.play()
        typealias B = IntroScore.Beat
        fadeIn()
        for (i, t) in B.arrive.enumerated() { later(t - 0.12) { [weak self] in self?.arrive(i + 1) } }
        later(B.word - 0.25) { [weak self] in self?.showWord() }
        later(B.retile - 0.1) { [weak self] in self?.retile() }
        later(B.gather) { [weak self] in self?.gather() }
        later(B.impact - 0.06) { [weak self] in self?.impact() }
    }

    func later(_ seconds: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        pending.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
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
        let panels = [dim!, word!] + tiles
        animate(seconds, curve: CAMediaTimingFunction(name: .easeOut), changes: { panels.forEach { $0.animator().alphaValue = 0 } }) {
            panels.forEach { $0.orderOut(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [fx] in fx?.orderOut(nil) }
    }

    func build() {
        let f = screen.frame
        dim = OuchPanel(role: .overlay(.above(.statusBar, 1), clickThrough: false), frame: f)
        let root = ClickView(frame: NSRect(origin: .zero, size: f.size))
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
        shade.colors = [Intro.graphite.withAlphaComponent(0.3).cgColor, Intro.graphite.withAlphaComponent(0.62).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.5)
        shade.endPoint = CGPoint(x: 1.1, y: 1.1)
        let shadeView = NSView(frame: root.bounds)
        shadeView.autoresizingMask = [.width, .height]
        shadeView.wantsLayer = true
        shade.frame = shadeView.bounds
        shade.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        shadeView.layer?.addSublayer(shade)
        root.addSubview(shadeView)
        skipLabel = NSTextField(labelWithString: "Click anywhere to skip")
        skipLabel.font = Theme.nsBody(12)
        skipLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        skipLabel.sizeToFit()
        skipLabel.setFrameOrigin(NSPoint(x: f.width - skipLabel.frame.width - 20, y: 18))
        skipLabel.alphaValue = 0
        root.addSubview(skipLabel)
        dim.contentView = root
        dim.alphaValue = 0

        let center = NSRect(x: f.midX, y: f.midY, width: 0, height: 0)
        for i in 0..<Self.count {
            let p = OuchPanel(role: .overlay(.above(.statusBar, 2), clickThrough: true), frame: padded(center))
            p.contentView = TileView(frame: NSRect(origin: .zero, size: p.frame.size), main: i == 0)
            p.alphaValue = 0
            tiles.append(p)
        }

        let size = max(64, min(140, f.width * 0.11))
        wordFrame = NSRect(x: f.minX, y: f.midY - 150, width: f.width, height: 300)
        word = OuchPanel(role: .overlay(.above(.statusBar, 3), clickThrough: true), frame: wordFrame.offsetBy(dx: 0, dy: -24))
        word.contentView = NSHostingView(rootView: WordmarkView(model: wordModel, size: size))
        word.alphaValue = 0

        fx = OuchPanel(role: .overlay(.above(.statusBar, 4), clickThrough: true), frame: f)
        fx.contentView = ImpactView(frame: NSRect(origin: .zero, size: f.size))
    }

    func tile(_ i: Int) -> TileView? { tiles.indices.contains(i) ? tiles[i].contentView as? TileView : nil }

    func padded(_ r: NSRect) -> NSRect { r.insetBy(dx: -Self.margin, dy: -Self.margin) }

    func move(_ i: Int, to r: NSRect, alpha: CGFloat, duration: Double, delay: Double = 0,
                      curve: CAMediaTimingFunction? = nil) {
        let p = tiles[i], c = curve ?? self.curve
        let run = {
            animate(duration, curve: c) { p.animator().setFrame(self.padded(r), display: true) }
            animate(min(duration, 0.4), curve: CAMediaTimingFunction(name: .easeOut)) { p.animator().alphaValue = alpha }
        }
        if delay > 0 { later(delay, run) } else { run() }
    }

}
