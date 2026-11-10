import AppKit
import CatWMKit
import SwiftUI

struct SortFullscreenLane: View {
    @ObservedObject var model: SortModel
    let item: SortItem
    let rows: Int

    private var carry: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
            .onChanged { model.dragChanged(item, $0) }
            .onEnded { _ in model.dragEnded() }
    }

    var body: some View {
        let lit = model.hover == item.id || model.selected == item.id
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(Theme.symbol(Theme.Icon.extraLarge, .regular))
                    .foregroundStyle(Theme.inkMuted).fixedSize()
                Text(item.app).font(Theme.heading()).foregroundStyle(Theme.ink).oneLine()
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .gesture(carry)
            SortThumb(layout: .fullscreen, ids: [item.id], lit: lit ? item.id : nil)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture { model.openFullscreen(item.id) }
                .gesture(carry)
            Text("Full screen").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine().padding(.leading, 4)
                .contentShape(Rectangle())
                .gesture(carry)
            VStack(spacing: 0) {
                SortRowFace(item: item, closing: false)
                    .padding(.leading, Theme.Space.extraSmall).padding(.trailing, 8)
                    .frame(height: SortMetrics.rowHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(lit ? Theme.hover : .clear))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside {
                            model.hover = item.id
                        } else if model.hover == item.id, model.drag == nil {
                            model.hover = nil
                        }
                    }
                    .zone(.row(item.id))
                    .onTapGesture(count: 2) { model.openFullscreen(item.id) }
                    .onTapGesture { model.selected = item.id }
                    .gesture(carry)
                    .accessibilityLabel("\(item.title), \(item.app), full screen")
                Spacer(minLength: 0)
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.surfaceRaised))
        .opacity(model.drag?.id == item.id ? 0.3 : 1)
    }
}
