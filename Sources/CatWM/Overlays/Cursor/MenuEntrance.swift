import AppKit
import SwiftUI

struct MenuEntrance: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).animation(shown ? Motion.fade : Motion.exit, value: shown)
    }
}
