import AppKit
import SwiftUI

struct TileProgress: ViewModifier, Animatable {
    var progress: Double
    let shown: Bool
    let surface: Bool
    var spread: CGSize = .zero

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let config = WindowManager.shared.config
        let eased = CGFloat(shown ? config.animationCurve.progress(progress, bounce: config.animationBounce) : progress)
        if surface {
            content
                .scaleEffect(x: 0.5 + 0.5 * eased, y: 0.35 + 0.65 * eased, anchor: .bottom)
                .opacity(min(1, progress * 4))
        } else {
            content.offset(x: spread.width * (1 - eased), y: spread.height * (1 - eased))
        }
    }
}
