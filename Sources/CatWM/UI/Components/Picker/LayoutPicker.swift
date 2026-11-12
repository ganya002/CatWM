import AppKit
import CatWMKit
import SwiftUI

struct LayoutPicker: View {
    let layouts: [Layout]
    let selection: Layout?
    var columns = 4
    let pick: (Layout) -> Void
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor final class Model: ObservableObject { @Published var hovered: Layout? }

    var body: some View {
        let shown = model.hovered ?? selection
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                ForEach(layouts, id: \.self) { layout in
                    Button { pick(layout) } label: {
                        LayoutThumbnail(layout: layout, selected: layout == selection)
                            .scaleEffect(model.hovered == layout && !reduceMotion ? 1.06 : 1)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(layout == selection ? Theme.accentSoft
                                      : model.hovered == layout ? Theme.hover : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        if hovering { model.hovered = layout } else if model.hovered == layout { model.hovered = nil }
                    }
                    .animation(reduceMotion ? Motion.fade : Motion.spring, value: model.hovered == layout)
                    .accessibilityLabel(layout.title)
                    .accessibilityAddTraits(layout == selection ? .isSelected : [])
                }
            }
            if let shown {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shown.title).font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink)
                            .oneLine().fixedSize()
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

#if DEBUG
extension GalleryExamples {
    static let tiling = GalleryExample(order: 12) { AnyView(GalleryContent(model: $0).tiling) }
}

extension GalleryContent {
    @ViewBuilder var tiling: some View {
        block("Tiling") {
            workspaceExample
            LayoutPicker(layouts: Layout.allCases, selection: model.layout, columns: 5) { model.layout = $0 }
                .frame(width: 320)
            thumbnailExamples
        }
    }
}
#endif

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
        case .dwindle: "Each new window splits the focused one, Hyprland style"
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
