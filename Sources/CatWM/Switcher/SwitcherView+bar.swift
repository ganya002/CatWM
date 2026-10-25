import AppKit
import SwiftUI

extension SwitcherView {
    func bar(_ layout: BarLayout) -> some View {
        VStack(spacing: Theme.Space.extraSmall) {
            if layout.scrolls {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) { tiles(layout) }
                        .scrollIndicators(.never)
                        .onChange(of: model.selection) { _, _ in
                            if let id = model.selected?.id { withAnimation(change) { proxy.scrollTo(id) } }
                        }
                }
            } else {
                tiles(layout)
            }
            if model.selected == nil {
                Text("No windows").textStyle(.caption).foregroundStyle(Theme.inkMuted).frame(height: Theme.rowHeight)
            } else {
                Color.clear.frame(height: Theme.rowHeight)
            }
        }
        .overlayPreferenceValue(SelectedTile.self) { anchor in
            GeometryReader { space in
                if let anchor, let item = model.selected {
                    let width = space.size.width, center = space[anchor].midX
                    titleLine(item)
                        .alignmentGuide(.leading) { label in
                            label.width / 2 - min(max(center, label.width / 2), width - label.width / 2)
                        }
                        .frame(width: width, height: space.size.height, alignment: .bottomLeading)
                        .animation(change, value: model.selection)
                }
            }
        }
    }

    private func tiles(_ layout: BarLayout) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(model.results, layout.widths).enumerated()), id: \.element.0.id) { index, tile in
                barTile(tile.0, size: CGSize(width: tile.1, height: layout.height), selected: index == model.selection)
                    .id(tile.0.id)
            }
        }
        .animation(change, value: model.selection)
    }

    private func barTile(_ item: SwitcherItem, size: CGSize, selected: Bool) -> some View {
        Button { model.onPick?(item) } label: {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.hover)
                        .matchedGeometryEffect(id: "selection", in: morph)
                    ring
                }
                if model.previewing {
                    previewFace(item, size: size)
                } else {
                    appIcon(item.pid, size: (min(size.width, size.height) * Tile.iconShare).rounded())
                        .matchedGeometryEffect(id: item.id, in: morph)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .anchorPreference(key: SelectedTile.self, value: .bounds) { selected ? $0 : nil }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var ring: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .padding(Tile.inner - 4)
            .matchedGeometryEffect(id: "ring", in: morph)
    }

    private func previewFace(_ item: SwitcherItem, size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            ZStack {
                shape.fill(Theme.well)
                if let shot = model.previews[item.id] {
                    Image(nsImage: shot).resizable().interpolation(.medium).scaledToFit()
                        .frame(maxWidth: item.size.width > 0 ? item.size.width : nil,
                               maxHeight: item.size.height > 0 ? item.size.height : nil)
                        .clipShape(shape)
                        .matchedGeometryEffect(id: "shot\(item.id)", in: morph)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width - Tile.inner * 2, height: size.height - Tile.inner * 2)
            .animation(fade, value: model.previews[item.id] != nil)
            appIcon(item.pid, size: (min(size.width, size.height) * Tile.badgeShare).rounded())
                .matchedGeometryEffect(id: item.id, in: morph)
                .offset(x: -Theme.Space.extraSmall, y: Theme.Space.extraSmall)
        }
    }
}

private struct SelectedTile: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}
