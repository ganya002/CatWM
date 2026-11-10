import AppKit
import CatWMKit
import SwiftUI

struct SortList: View {
    @ObservedObject var model: SortModel
    let ids: [CGWindowID]
    let closing: Bool
    let rows: Int

    var body: some View {
        let items = ids.compactMap { model.plan.items[$0] }
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: items.count > model.maxRows) {
                VStack(spacing: 0) {
                    if items.isEmpty && !closing {
                        RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(0.5).frame(height: SortMetrics.rowHeight)
                    }
                    ForEach(blocks, id: \.self) { block in
                        if let lead = model.plan.items[block[0]], model.plan.isTabbed(lead.id) {
                            VStack(spacing: 0) {
                                SortTabHeader(model: model, lead: lead, count: block.count)
                                rows(block)
                            }
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                .fill(model.over == .tabs(lead.id) ? Theme.accentSoft : .clear))
                            .zone(.tabs(lead.id))
                            .animation(Motion.fadeMedium, value: model.over)
                        } else {
                            rows(block)
                        }
                    }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight)
            .onChange(of: model.reveal) { _, reveal in
                if ids.contains(reveal.id) { withAnimation(Motion.user) { proxy.scrollTo(reveal.id) } }
            }
        }
    }

    private var blocks: [[CGWindowID]] {
        let known = ids.filter { model.plan.items[$0] != nil }
        return closing ? known.map { [$0] } : model.plan.tabBlocks(known)
    }

    private func rows(_ block: [CGWindowID]) -> some View {
        ForEach(block.compactMap { model.plan.items[$0] }) { item in
            SortRow(model: model, item: item, closing: closing, tab: tab(of: item.id, in: block)).id(item.id)
        }
    }

    private func tab(of id: CGWindowID, in block: [CGWindowID]) -> SortRow.Tab? {
        guard !closing, model.plan.isTabbed(id) else { return nil }
        return block.last == id ? .last : .middle
    }
}
