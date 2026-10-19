import AppKit
import SwiftUI

struct SortRow: View {
    @ObservedObject var model: SortModel
    let item: SortItem
    let closing: Bool
    var indented = false

    var body: some View {
        let pointed = model.hover == item.id
        let lit = pointed || model.selected == item.id
        SortRowFace(item: item, closing: closing)
            .padding(.leading, indented ? 19 : 5).padding(.trailing, 8)
            .frame(height: SortMetrics.rowHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(closing ? (pointed ? Theme.hover : .clear) : lit ? Theme.accentSoft : .clear))
            .overlay(alignment: .trailing) {
                if pointed && model.drag == nil {
                    RemoveButton(help: closing ? "Bring back" : "Close window", variant: closing ? .restore : .close) {
                        if closing { model.restore(item.id) } else { model.markClosing(item.id) }
                    }
                    .padding(.trailing, 2)
                    .transition(.opacity)
                }
            }
            .opacity(model.drag?.id == item.id ? 0.3 : 1)
            .contentShape(Rectangle())
            .zone(.row(item.id))
            .onHover { inside in
                if inside {
                    model.hover = item.id
                } else if model.hover == item.id, model.drag == nil {
                    model.hover = nil
                }
            }
            .onTapGesture { if closing { model.restore(item.id) } else { model.selected = item.id } }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
                .onChanged { model.dragChanged(item, $0) }
                .onEnded { _ in model.dragEnded() })
            .tooltip(closing ? "Click to bring back" : "")
            .accessibilityLabel("\(item.title), \(item.app)")
    }
}
