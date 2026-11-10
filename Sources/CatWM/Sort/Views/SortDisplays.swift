import AppKit
import CatWMKit
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
                         action: { withAnimation(Motion.user) { model.use(display.id) } },
                         lead: { ink in SortScreenGlyph(display: display, color: ink).padding(.trailing, 2) })
                .zone(.display(display.id))
                .accessibilityLabel(display.name)
            }
        }
    }
}

struct SortScreenGlyph: View {
    let display: SortDisplay
    let color: Color

    var body: some View {
        let width = min(24, max(16, (12 * display.aspect).rounded()))
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous) // style-ok: a 12pt drawing of a screen
                .strokeBorder(color, lineWidth: 1.5).frame(width: width, height: 12)
            Capsule().fill(color).frame(width: display.isLaptop ? width + 5 : 6, height: 1.5)
        }
        .frame(height: 16)
    }
}
