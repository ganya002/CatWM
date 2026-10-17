import AppKit
import SwiftUI

struct MenuEntrance: ViewModifier {
    let shown: Bool
    let from: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(Motion.fadeMedium, value: shown)
        } else {
            content
                .opacity(shown ? 1 : 0)
                .animation(shown ? Motion.fade : Motion.exit, value: shown)
                .scaleEffect(shown ? 1 : 0.12, anchor: from)
                .animation(shown ? Motion.pop : .timingCurve(0.4, 0, 1, 1, duration: 0.14), value: shown)
        }
    }
}
