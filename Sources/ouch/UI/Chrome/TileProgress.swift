import AppKit
import SwiftUI

struct TileProgress: ViewModifier, Animatable {
    var t: Double
    let shown: Bool
    let surface: Bool
    var spread: CGSize = .zero

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func body(content: Content) -> some View {
        let c = WindowManager.shared.config
        let e = CGFloat(shown ? c.animationCurve.progress(t, bounce: c.animationBounce) : t)
        if surface {
            content
                .scaleEffect(x: 0.5 + 0.5 * e, y: 0.35 + 0.65 * e, anchor: .bottom)
                .opacity(min(1, t * 4))
        } else {
            content.offset(x: spread.width * (1 - e), y: spread.height * (1 - e))
        }
    }
}
