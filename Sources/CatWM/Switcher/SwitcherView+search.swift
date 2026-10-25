import AppKit
import SwiftUI

extension SwitcherView {
    func search(room: CGSize) -> some View {
        VStack(spacing: 0) {
            head
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.bottom, Self.inset)
            list(room: room)
        }
    }

    private var head: some View {
        HStack(spacing: Theme.Space.small) {
            Image(systemName: "magnifyingglass").font(Theme.symbol()).foregroundStyle(Theme.inkMuted)
            Text(model.query).font(Theme.body(13.5)).foregroundStyle(Theme.ink).oneLine()
            Spacer(minLength: Theme.Space.small)
            if let filter {
                Text(filter).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.horizontal, Theme.Space.medium)
        .frame(height: Self.headHeight)
        .accessibilityElement(children: .combine)
    }

    private var filter: String? {
        let parts = [model.appFilter?.app, model.scope == .all ? nil : model.scope.label].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func list(room: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if model.results.isEmpty {
                        Text("No windows match").font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted)
                            .frame(maxWidth: .infinity, minHeight: Theme.rowHeight)
                    }
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == model.selection).id(item.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(CGFloat(max(model.results.count, 1)) * Theme.rowHeight,
                               room.height - Self.headHeight - 1 - Self.inset))
            .animation(change, value: model.results.count)
            .onChange(of: model.selection) { _, _ in
                if let id = model.selected?.id { proxy.scrollTo(id) }
            }
        }
    }

    private func row(_ item: SwitcherItem, selected: Bool) -> some View {
        OMenuRow(highlight: .fixed(selected), action: { model.onPick?(item) }, lead: {
            appIcon(item.pid, size: 16).matchedGeometryEffect(id: item.id, in: morph)
        }, label: {
            HStack(spacing: Theme.Space.small) {
                Text(item.title.isEmpty ? item.app : item.title).oneLine().layoutPriority(1)
                if !item.title.isEmpty {
                    Text(item.app).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
            }
        }, trailing: {
            if !item.workspace.isEmpty {
                Text(item.workspace).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
            }
        })
        .accessibilityLabel(label(item))
        .accessibilityValue(item.workspace.isEmpty ? "" : "Workspace \(item.workspace)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
