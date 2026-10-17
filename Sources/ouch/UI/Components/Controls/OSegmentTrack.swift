import AppKit
import SwiftUI

struct OSegmentTrack<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Theme.Space.xxs) { content }
            .padding(3)
            .background(Capsule().fill(Theme.well))
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(title)
    }
}
