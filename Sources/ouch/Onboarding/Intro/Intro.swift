import AppKit
import SwiftUI

final class Intro {

    static let margin: CGFloat = 60
    static let count = 5

    let screen: NSScreen
    let landing: NSRect
    let onDone: () -> Void
    let score: IntroScore
    var dim: OuchPanel!
    var skipLabel: NSTextField!
    var tiles: [OuchPanel] = []
    var word: OuchPanel!
    var fx: OuchPanel!
    let wordModel = WordmarkModel()
    var wordFrame = NSRect.zero
    var pending: [DispatchWorkItem] = []
    var done = false

    let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.15, 1)

    static let graphite = Theme.nsFixed(\.bg, dark: true)

    init(screen: NSScreen, landing: NSRect, music: IntroScore.Arrangement = .standard, onDone: @escaping () -> Void) {
        self.screen = screen
        self.landing = landing
        self.onDone = onDone
        score = IntroScore(music)
        build()
    }

}
