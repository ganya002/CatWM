import AppKit
import SwiftUI

struct LayoutPicker: View {
    let layouts: [Layout]
    let selection: Layout?
    var columns = 4
    let pick: (Layout) -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject { @Published var hovered: Layout? }

    var body: some View {
        let shown = model.hovered ?? selection
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(layouts, id: \.self) { l in
                    Button { pick(l) } label: {
                        LayoutThumbnail(layout: l, selected: l == selection)
                            .scaleEffect(model.hovered == l ? 1.06 : 1)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .fill(l == selection ? Theme.accentSoft : model.hovered == l ? Theme.wellHover : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { on in
                        if on { model.hovered = l } else if model.hovered == l { model.hovered = nil }
                    }
                    .animation(Motion.spring, value: model.hovered == l)
                    .accessibilityLabel(l.title)
                    .accessibilityAddTraits(l == selection ? .isSelected : [])
                }
            }
            if let shown {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shown.title).font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink).oneLine().fixedSize()
                        Text(shown.blurb).font(Theme.body(12)).foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
                    }
                    Text(shown.title).font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink).oneLine()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 2)
            }
        }
    }
}

extension Layout {
    var blurb: String {
        switch self {
        case .tall: "Main left, the rest stacked right"
        case .tallRight: "Main right, the rest stacked left"
        case .wide: "Main on top, the rest below"
        case .middleWide: "Main in the middle, the rest beside"
        case .fullscreen: "Every window fills the screen"
        case .column: "Equal-width columns"
        case .row: "Equal-height rows"
        case .floating: "Windows stay where you put them"
        case .bsp: "Each window halves the last one"
        case .threeColumnLeft: "Main left, two columns right"
        case .threeColumnMiddle: "Main in the middle column"
        case .threeColumnRight: "Main right, two columns left"
        case .twoPane: "Main left, one window right"
        case .twoPaneRight: "Main right, one window left"
        case .widescreenTall: "Mains side by side, the rest right"
        case .widescreenTallRight: "Mains side by side, the rest left"
        }
    }
}
