import AppKit
import SwiftUI

struct SortTabHeader: View {
    @ObservedObject var model: SortModel
    let lead: SortItem
    let count: Int

    var body: some View {
        SortTabHeaderFace(count: count)
            .padding(.leading, 5).padding(.trailing, 8)
            .frame(height: SortMetrics.rowHeight)
            .opacity(model.drag?.group.isEmpty == false && model.drag?.id == lead.id ? 0.3 : 1)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
                .onChanged { model.dragChanged(lead, $0, group: true) }
                .onEnded { _ in model.dragEnded() })
            .tooltip("Drag to move the whole group")
            .accessibilityLabel("Tab group, \(count) tabs")
    }
}

struct SortTabHeaderFace: View {
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack")
                .font(Theme.symbol(Theme.Icon.small))
                .foregroundStyle(Theme.inkMuted)
                .frame(width: 20, height: 20)
            Text("Tab group").foregroundStyle(Theme.ink).oneLine()
            Spacer(minLength: 0)
            Text(count == 1 ? "1 tab" : "\(count) tabs")
                .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
        }
        .font(Theme.body(13.5, .medium))
    }
}
