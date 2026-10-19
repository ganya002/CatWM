import AppKit
import SwiftUI

struct SortCloseList: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    let rows: Int

    var body: some View {
        let grouped = Set(plan.closedLanes.flatMap(\.ids))
        ScrollViewReader { proxy in
            let extraRows = Int(SortMetrics.closeExtra / SortMetrics.rowHeight)
            let overflows = plan.close.count + plan.closedLanes.count > rows + extraRows
            ScrollView(.vertical, showsIndicators: overflows) {
                VStack(spacing: 0) {
                    ForEach(plan.closedLanes) { group in
                        SortClosedHeader(model: model, group: group)
                        ForEach(group.ids.compactMap { plan.items[$0] }) { item in
                            SortRow(model: model, item: item, closing: true, indented: true).id(item.id)
                        }
                    }
                    ForEach(plan.close.filter { !grouped.contains($0) }.compactMap { plan.items[$0] }) { item in
                        SortRow(model: model, item: item, closing: true).id(item.id)
                    }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight + SortMetrics.closeExtra)
            .onChange(of: model.reveal) { _, reveal in
                if plan.close.contains(reveal.id) || grouped.contains(reveal.id) {
                    withAnimation(Motion.easeOut) { proxy.scrollTo(reveal.id) }
                }
            }
        }
    }
}
