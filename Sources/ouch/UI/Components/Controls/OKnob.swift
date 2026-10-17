import AppKit
import SwiftUI

struct OKnob: View {
    var color: Color? = nil
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let color {
                Circle().fill(color).overlay(Circle().strokeBorder(.white, lineWidth: 2)).elevation(.knob, in: Circle())
            } else {
                Circle().fill(Theme.surfaceRaised)
                    .elevation(.sm, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.borderControl.opacity(0.75), lineWidth: 1))
            }
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var knobExamples: some View {
        OKnob()
        OKnob(color: Theme.accent)
    }
}
#endif
