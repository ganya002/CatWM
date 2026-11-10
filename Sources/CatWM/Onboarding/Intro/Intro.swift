import AppKit
import CatWMKit
import SwiftUI

final class Intro {
    static let margin: CGFloat = 60
    static let count = 5

    let screen: NSScreen
    let landing: NSRect
    let onDone: () -> Void
    let score: IntroScore
    let dim: CatWMPanel
    let skipLabel = NSTextField(labelWithString: "Click anywhere to skip")
    var tiles: [CatWMPanel] = []
    let word: CatWMPanel
    let effects: CatWMPanel
    let wordModel = WordmarkModel()
    let wordFrame: NSRect
    var pending: [DispatchWorkItem] = []
    var done = false

    let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.15, 1)

    static let graphite = Theme.nsFixed(\.background, dark: true)

    init(screen: NSScreen, landing: NSRect, music: IntroScore.Arrangement = .standard,
         onDone: @escaping () -> Void) {
        self.screen = screen
        self.landing = landing
        self.onDone = onDone
        score = IntroScore(music)
        let frame = screen.frame
        dim = CatWMPanel(role: .overlay(.above(.statusBar, 1), clickThrough: false), frame: frame)
        wordFrame = NSRect(x: frame.minX, y: frame.midY - 150, width: frame.width, height: 300)
        word = CatWMPanel(role: .overlay(.above(.statusBar, 3), clickThrough: true),
                         frame: wordFrame.offsetBy(dx: 0, dy: -24))
        effects = CatWMPanel(role: .overlay(.above(.statusBar, 4), clickThrough: true), frame: frame)
        build()
    }
}

final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
    override func mouseDown(with _: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}
