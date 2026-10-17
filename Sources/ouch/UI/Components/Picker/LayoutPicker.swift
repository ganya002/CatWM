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

#if DEBUG
extension GalleryExamples {
    static let tiling = GalleryExample(order: 12) { AnyView(GalleryContent(m: $0).tiling) }
}

extension GalleryContent {
    @ViewBuilder var tiling: some View {
        block("Tiling") {
            workspaceExample
            LayoutPicker(layouts: Layout.allCases, selection: m.layout, columns: 5) { m.layout = $0 }
                .frame(width: 320)
            thumbnailExamples
        }
    }
}
#endif
