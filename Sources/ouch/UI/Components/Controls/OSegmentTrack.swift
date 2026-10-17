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

#if DEBUG
extension GalleryContent {
    @ViewBuilder var segmentTrackExamples: some View {
        OSegmentTrack(title: "Filter") {
            OSegment(label: "All", count: 12, on: true) {}
            OSegment(label: "Floating", count: 3, on: false) {}
            OSegment(label: "Needs review", on: false, hot: true) {}
        }
    }
}
#endif
