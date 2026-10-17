import AppKit
import SwiftUI

struct PressScale: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.spring, value: configuration.isPressed)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var pressScaleExample: some View {
        Button {} label: { Text("Press scale").padding(Theme.Space.md).background(Capsule().fill(Theme.well)) }
            .buttonStyle(PressScale())
    }
}
#endif
