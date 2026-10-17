import AppKit
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
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(0.5).frame(height: SortMetrics.rowHeight)
                    }
                    ForEach(items) { item in SortRow(model: model, item: item, closing: closing).id(item.id) }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight)
            .onChange(of: model.reveal) { _, r in
                if ids.contains(r.id) { withAnimation(Motion.easeOut) { proxy.scrollTo(r.id) } }
            }
        }
    }
}
