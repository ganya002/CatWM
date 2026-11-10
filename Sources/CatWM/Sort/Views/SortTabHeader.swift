import AppKit
import CatWMKit
import SwiftUI

struct SortTabHeader: View {
    @ObservedObject var model: SortModel
    let lead: SortItem
    let count: Int
    var closing = false
    @StateObject private var hover = Flag()
    @StateObject private var menu = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SortTabHeaderFace(count: count)
            .padding(.leading, Theme.Space.extraSmall).padding(.trailing, 8)
            .frame(height: SortMetrics.rowHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill((closing && hover.isOn) || menu.isOn ? Theme.hover : .clear))
            .overlay(alignment: .trailing) {
                if closing && hover.isOn && model.drag == nil {
                    RemoveButton(help: "Bring back", variant: .restore, tooltip: false) { model.restore(lead.id) }
                        .padding(.trailing, 2)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                            .fill(Theme.hover))
                        .transition(.opacity)
                }
            }
            .opacity(model.drag?.group.isEmpty == false && model.drag?.id == lead.id ? 0.3 : 1)
            .contentShape(Rectangle())
            .onHover { hover.isOn = $0 }
            .onTapGesture { if closing { model.restore(lead.id) } }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
                .onChanged { model.dragChanged(lead, $0, group: true) }
                .onEnded { _ in model.dragEnded() })
            .oContextMenu(opened: { menu.isOn = $0 }, items: {
                model.tabGroupMenu(lead: lead.id, closing: closing) { change in
                    withAnimation(Motion.user(reduceMotion: reduceMotion), change)
                }
            })
            .accessibilityLabel("Tab group, \(count) tabs")
            .accessibilityAddTraits(closing ? .isButton : [])
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
