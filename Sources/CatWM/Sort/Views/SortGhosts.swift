import AppKit
import CatWMKit
import SwiftUI

struct SortGhosts: View {
    @ObservedObject var model: SortModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ghost
            columnGhost
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
    }

    private func tint(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Theme.danger)
            .opacity(model.dragOutside ? 0.18 : 0)
            .animation(Motion.fadeMedium, value: model.dragOutside)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var columnGhost: some View {
        if let dragged = model.columnDrag {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(dragged.lane.number).font(Theme.display(22)).monospacedDigit().tracking(-0.4)
                        .foregroundStyle(Theme.ink).fixedSize()
                    Text(dragged.lane.name.isEmpty ? "Workspace \(dragged.lane.number)" : dragged.lane.name)
                        .font(Theme.heading()).oneLine()
                }
                .padding(.horizontal, 2)
                SortThumb(layout: dragged.lane.layout, ids: dragged.lane.ids, lit: nil,
                          ratio: dragged.ratio, mainCount: dragged.mainCount)
                    .padding(.horizontal, 2)
            }
            .padding(.vertical, 2)
            .frame(width: SortMetrics.lane - 12, alignment: .topLeading)
            .surface(.medium)
            .overlay { tint(radius: Theme.Radius.large) }
            .keepInside(CGPoint(x: dragged.location.x - dragged.grab.width + model.ghostShift.width,
                                y: dragged.location.y - dragged.grab.height + model.ghostShift.height))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var ghost: some View {
        if let dragged = model.drag {
            VStack(spacing: 0) {
                if dragged.group.isEmpty {
                    SortRowFace(item: dragged.item, closing: dragged.closing)
                        .padding(.leading, Theme.Space.extraSmall).padding(.trailing, 8)
                        .frame(height: SortMetrics.rowHeight)
                } else {
                    SortTabHeaderFace(count: dragged.group.count)
                        .padding(.leading, Theme.Space.extraSmall).padding(.trailing, 8)
                        .frame(height: SortMetrics.rowHeight)
                    ForEach(dragged.group) { item in
                        SortRowFace(item: item, closing: false)
                            .padding(.leading, SortMetrics.tabIndent).padding(.trailing, 8)
                            .frame(height: SortMetrics.rowHeight)
                            .background(alignment: .leading) {
                                SortTabBracket(last: item.id == dragged.group.last?.id)
                            }
                    }
                }
            }
            .frame(width: 168)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.surfaceRaised)
                .elevation(.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)))
            .overlay { tint(radius: Theme.Radius.small) }
            .keepInside(CGPoint(x: dragged.location.x - dragged.grab.width + model.ghostShift.width,
                                y: dragged.location.y - dragged.grab.height + model.ghostShift.height))
            .allowsHitTesting(false)
        }
    }
}
