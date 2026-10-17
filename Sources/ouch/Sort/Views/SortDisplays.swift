import AppKit
import SwiftUI

struct SortDisplays: View {
    @ObservedObject var model: SortModel
    @Namespace private var thumb

    var body: some View {
        OSegmentTrack(title: "Display to sort") {
            ForEach(model.displays) { d in
                let on = d.id == model.current
                OSegment(label: d.short, count: model.count(of: d.id), on: on, hot: model.over == .display(d.id) && !on,
                         thumb: thumb, action: { withAnimation(Motion.spring) { model.use(d.id) } }) { ink in
                    SortScreenGlyph(display: d, color: ink).padding(.trailing, 2)
                }
                .zone(.display(d.id))
                .tooltip(d.name)
                .accessibilityLabel(d.name)
            }
        }
    }
}
