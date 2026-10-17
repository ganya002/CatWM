import AppKit
import SwiftUI

final class IntroLabModel: ObservableObject {
    @Published var playing: String?
    private var score: IntroScore?

    func music(_ a: IntroScore.Arrangement) {
        stop()
        let s = IntroScore(a)
        s.play()
        score = s
        playing = a.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self, weak s] in
            if let self, self.score === s { self.score = nil; self.playing = nil }
        }
    }

    func intro(_ a: IntroScore.Arrangement) {
        stop()
        Onboarding.shared.playIntro(a)
    }

    func stop() {
        score?.fadeOut(over: 0.3)
        score = nil
        playing = nil
    }
}
