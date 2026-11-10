import AppKit
import CatWMKit
import SwiftUI

struct SortCloseList: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    let rows: Int

    var body: some View {
        let grouped = Set(plan.closedLanes.flatMap(\.ids))
        ScrollViewReader { proxy in
            let extraRows = Int(SortMetrics.closeExtra / SortMetrics.rowHeight)
            let overflows = plan.closeRowCount > rows + extraRows
            ScrollView(.vertical, showsIndicators: overflows) {
                VStack(spacing: 0) {
                    ForEach(plan.closedLanes) { group in
                        SortClosedHeader(model: model, group: group)
                        blocks(group.ids, indented: true)
                    }
                    blocks(plan.close.filter { !grouped.contains($0) }, indented: false)
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight + SortMetrics.closeExtra)
            .onChange(of: model.reveal) { _, reveal in
                if plan.close.contains(reveal.id) || grouped.contains(reveal.id) {
                    withAnimation(Motion.user) { proxy.scrollTo(reveal.id) }
                }
            }
        }
    }

    private func blocks(_ ids: [CGWindowID], indented: Bool) -> some View {
        ForEach(plan.closeBlocks(ids.filter { plan.items[$0] != nil }), id: \.self) { block in
            if block.count > 1, let lead = plan.items[block[0]] {
                VStack(spacing: 0) {
                    SortTabHeader(model: model, lead: lead, count: block.count, closing: true)
                    ForEach(block.compactMap { plan.items[$0] }) { item in
                        SortRow(model: model, item: item, closing: true,
                                tab: item.id == block.last ? .last : .middle).id(item.id)
                    }
                }
                .padding(.leading, indented ? SortMetrics.closedIndent : 0)
            } else if let item = plan.items[block[0]] {
                SortRow(model: model, item: item, closing: true, indented: indented).id(item.id)
            }
        }
    }
}

struct SortClosedHeader: View {
    @ObservedObject var model: SortModel
    let group: SortClosedLane
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(spacing: 8) {
            Text(group.number).textStyle(.sectionTitle).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
            Text(group.name.isEmpty ? "Workspace \(group.number)" : group.name).font(Theme.body(13.5, .medium))
                .foregroundStyle(Theme.inkMuted).strikethrough(true, color: Theme.danger).oneLine()
            Spacer(minLength: 0)
            Text(group.ids.isEmpty ? "" : "\(group.ids.count)")
                .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
        }
        .padding(.leading, Theme.Space.extraSmall).padding(.trailing, 8)
        .frame(height: SortMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(hover.isOn ? Theme.hover : .clear))
        .overlay(alignment: .trailing) {
            if hover.isOn {
                RemoveButton(help: "Bring back", variant: .restore, tooltip: false) { model.reopen(group.id) }
                    .padding(.trailing, 2)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.hover))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
        .onTapGesture { model.reopen(group.id) }
        .accessibilityLabel("Closed workspace \(group.number), \(group.ids.count) windows")
        .accessibilityAddTraits(.isButton)
    }
}
