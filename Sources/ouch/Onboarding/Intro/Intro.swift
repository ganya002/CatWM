import AppKit
import SwiftUI

final class Intro {
    static let margin: CGFloat = 60
    static let count = 5

    let screen: NSScreen
    let landing: NSRect
    let onDone: () -> Void
    let score: IntroScore
    let dim: OuchPanel
    let skipLabel = NSTextField(labelWithString: "Click anywhere to skip")
    var tiles: [OuchPanel] = []
    let word: OuchPanel
    let effects: OuchPanel
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
        dim = OuchPanel(role: .overlay(.above(.statusBar, 1), clickThrough: false), frame: frame)
        wordFrame = NSRect(x: frame.minX, y: frame.midY - 150, width: frame.width, height: 300)
        word = OuchPanel(role: .overlay(.above(.statusBar, 3), clickThrough: true),
                         frame: wordFrame.offsetBy(dx: 0, dy: -24))
        effects = OuchPanel(role: .overlay(.above(.statusBar, 4), clickThrough: true), frame: frame)
        build()
    }
}
