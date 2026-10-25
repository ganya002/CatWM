import AppKit
import SwiftUI

final class IntroLabModel: ObservableObject {
    @Published var playing: String?
    private var score: IntroScore?

    func music(_ arrangement: IntroScore.Arrangement) {
        stop()
        let started = IntroScore(arrangement)
        started.play()
        score = started
        playing = arrangement.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self, weak started] in
            if let self, self.score === started { self.score = nil; self.playing = nil }
        }
    }

    func intro(_ arrangement: IntroScore.Arrangement) {
        stop()
        Onboarding.shared.playIntro(arrangement)
    }

    func stop() {
        score?.fadeOut(over: 0.3)
        score = nil
        playing = nil
    }
}
