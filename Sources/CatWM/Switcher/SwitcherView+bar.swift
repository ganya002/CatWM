import AppKit
import SwiftUI

extension SwitcherView {
    var bar: some View {
        VStack(spacing: Theme.Space.extraSmall) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                            barTile(item, selected: index == model.selection).id(item.id)
                        }
                    }
                    .animation(change, value: model.selection)
                }
                .scrollIndicators(.never)
                .frame(height: tile.height)
                .onChange(of: model.selection) { _, selection in
                    guard let id = model.selected?.id, let first = model.results.first?.id else { return }
                    withAnimation(change) {
                        if selection <= 1 { proxy.scrollTo(first, anchor: .leading) } else { proxy.scrollTo(id) }
                    }
                }
            }
            if let item = model.selected {
                titleLine(item)
            } else {
                Text("No windows").textStyle(.caption).foregroundStyle(Theme.inkMuted).frame(height: Theme.rowHeight)
            }
        }
    }

    private func barTile(_ item: SwitcherItem, selected: Bool) -> some View {
        Button { model.onPick?(item) } label: {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.hover)
                        .matchedGeometryEffect(id: "selection", in: morph)
                    ring
                }
                if model.previewing {
                    previewFace(item)
                } else {
                    appIcon(item.pid, size: tile.iconSize).matchedGeometryEffect(id: item.id, in: morph)
                }
            }
            .frame(width: tileWidth(item), height: tile.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(item))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var ring: some View {
        let gap = model.previewing ? Tile.inner - 4 : 0
        return RoundedRectangle(cornerRadius: model.previewing ? Theme.Radius.medium : Theme.Radius.small,
                                style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .padding(gap)
            .matchedGeometryEffect(id: "ring", in: morph)
    }

    private func previewFace(_ item: SwitcherItem) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.extraSmall, style: .continuous)
        return ZStack(alignment: .bottomLeading) {
            ZStack {
                shape.fill(Theme.well)
                if let shot = model.previews[item.id] {
                    Image(nsImage: shot).resizable().interpolation(.medium).scaledToFit()
                        .clipShape(shape)
                        .matchedGeometryEffect(id: "shot\(item.id)", in: morph)
                        .transition(.opacity)
                }
            }
            .frame(width: tileWidth(item) - Tile.inner * 2, height: tile.height - Tile.inner * 2)
            .animation(Motion.fade, value: model.previews[item.id] != nil)
            appIcon(item.pid, size: tile.iconSize)
                .matchedGeometryEffect(id: item.id, in: morph)
                .offset(x: -Theme.Space.extraSmall, y: Theme.Space.extraSmall)
        }
    }
}
