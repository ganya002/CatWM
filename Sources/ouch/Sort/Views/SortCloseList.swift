import AppKit
import SwiftUI

struct SortCloseList: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    let rows: Int

    var body: some View {
        let grouped = Set(plan.closedLanes.flatMap(\.ids))
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: plan.close.count + plan.closedLanes.count > rows + Int(SortMetrics.closeExtra / SortMetrics.rowHeight)) {
                VStack(spacing: 0) {
                    ForEach(plan.closedLanes) { g in
                        SortClosedHeader(model: model, group: g)
                        ForEach(g.ids.compactMap { plan.items[$0] }) { item in SortRow(model: model, item: item, closing: true, indented: true).id(item.id) }
                    }
                    ForEach(plan.close.filter { !grouped.contains($0) }.compactMap { plan.items[$0] }) { item in
                        SortRow(model: model, item: item, closing: true).id(item.id)
                    }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight + SortMetrics.closeExtra)
            .onChange(of: model.reveal) { _, r in
                if plan.close.contains(r.id) || grouped.contains(r.id) { withAnimation(Motion.easeOut) { proxy.scrollTo(r.id) } }
            }
        }
    }
}
