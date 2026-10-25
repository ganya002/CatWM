import AppKit
import SwiftUI

struct SortDisplays: View {
    @ObservedObject var model: SortModel
    @Namespace private var thumb

    var body: some View {
        OSegmentTrack(title: "Display to overview") {
            ForEach(model.displays) { display in
                let isCurrent = display.id == model.current
                OSegment(label: display.short, count: model.count(of: display.id), selected: isCurrent,
                         hot: model.over == .display(display.id) && !isCurrent, thumb: thumb,
                         action: { withAnimation(PanelMotion.windowAnimation) { model.use(display.id) } },
                         lead: { ink in SortScreenGlyph(display: display, color: ink).padding(.trailing, 2) })
                .zone(.display(display.id))
                .accessibilityLabel(display.name)
            }
        }
    }
}
