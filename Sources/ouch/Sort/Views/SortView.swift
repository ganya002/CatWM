import AppKit
import SwiftUI

struct SortView: View {
    @ObservedObject var model: SortModel
    let width: CGFloat
    static var inset: EdgeInsets {
        EdgeInsets(top: Elevation.float.room, leading: Elevation.float.room, bottom: 0, trailing: Elevation.float.room)
    }

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.xxl, topTrailingRadius: Theme.Radius.xxl,
                               style: .continuous)
    }

    var body: some View {
        let plan = model.plan
        let closeCount = CGFloat(plan.close.count + plan.closedLanes.count)
        let closeRows = Int(ceil(closeCount - SortMetrics.closeExtra / SortMetrics.rowHeight))
        let rows = min(model.maxRows, max(SortMetrics.minRows, ([closeRows] + plan.lanes.map(\.ids.count)).max() ?? 1))
        VStack(alignment: .leading, spacing: 0) {
            header(plan)
            HStack(alignment: .top, spacing: 4) {
                row(plan, rows: rows)
                closeLane(plan, rows: rows)
            }
            .padding(.top, 8).padding(.horizontal, -8)
        }
        .frame(width: width - 40)
        .padding(Density.large.padding)
        .padding(.top, Theme.Space.small)
        .background { Self.shape.fill(Theme.surface).elevation(.float, in: Self.shape) }
        .panelEntrance(model.shown, style: model.motion)
        .padding(Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topLeading) { ghost }
        .overlay(alignment: .topLeading) { columnGhost }
        .coordinateSpace(name: "sort")
        .onPreferenceChange(SortZoneKey.self) { model.zones = $0 }
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private func header(_ plan: SortPlan) -> some View {
        let count = plan.items.count
        return HStack(spacing: 12) {
            Text("Overview · \(count) window\(count == 1 ? "" : "s")")
                .textStyle(.title).monospacedDigit().oneLine().fixedSize()
            if model.displays.count > 1 { SortDisplays(model: model) }
            notices(plan)
            Spacer(minLength: 12)
        }
        .padding(.bottom, 4)
    }

    private func row(_ plan: SortPlan, rows: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(plan.lanes.enumerated()), id: \.element.id) { i, lane in
                        SortLaneView(model: model, index: i, lane: lane, rows: rows).id(lane.id)
                            .tileItem(model.shown, style: model.motion,
                                      spread: CGSize(width: -CGFloat(i) * (SortMetrics.lane + 4), height: 0))
                    }
                    SortAddLane(model: model, plan: plan, rows: rows)
                        .tileItem(model.shown, style: model.motion,
                                  spread: CGSize(width: -CGFloat(plan.lanes.count) * (SortMetrics.lane + 4), height: 0))
                    ForEach(Array(unplacedFullscreen(plan).enumerated()), id: \.element.id) { i, item in
                        SortFullscreenLane(model: model, item: item, rows: rows)
                            .tileItem(model.shown, style: model.motion,
                                      spread: CGSize(width: -CGFloat(plan.lanes.count + 1 + i) * (SortMetrics.lane + 4),
                                                     height: 0))
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
                .background(SortScrollAccessor(model: model))
            }
            .zone(.scroller)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    if model.moreToRight {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                }
            }
            .onChange(of: model.reveal) { _, reveal in
                guard let lane = reveal.lane else { return }
                withAnimation(Motion.easeOut) { proxy.scrollTo(lane) }
            }
        }
    }

    private func unplacedFullscreen(_ plan: SortPlan) -> [SortItem] {
        (model.currentDisplay?.fullscreen ?? []).filter { plan.items[$0.id] == nil }
    }

    private func closeLane(_ plan: SortPlan, rows: Int) -> some View {
        let over = model.over == .close
        let count = plan.close.count
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
        return VStack(alignment: .trailing, spacing: SortMetrics.closeGap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(Image(systemName: "xmark")).font(Theme.display(22)).foregroundStyle(Theme.danger).fixedSize()
                    Text("Close").font(Theme.heading()).foregroundStyle(Theme.ink).oneLine()
                    Text(count > 0 ? "\(count)" : "")
                        .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
                }
                .padding(.horizontal, 4)
                SortCloseList(model: model, plan: plan, rows: rows)
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(width: SortMetrics.lane, alignment: .topLeading)
            .background(shape.fill(over ? Theme.dangerSoft : Theme.surfaceRaised))
            .animation(Motion.fadeMedium, value: over)
            .zone(.close)
            HStack(spacing: 4) {
                OButton("Revert", variant: .ghost, size: .small, shortcut: ["esc"]) { model.revert() }
                OButton("Done", variant: .primary, size: .small, shortcut: ["⏎"]) { model.finish(nil) }
            }
            .font(Theme.body(13.5))
        }
        .frame(width: SortMetrics.lane)
        .padding(.leading, 4).padding(.trailing, 8)
    }

    private func notices(_ plan: SortPlan) -> some View {
        HStack(spacing: 8) {
            if let text = plan.duplicateText {
                OButton(text, icon: "xmark.circle", variant: .ghost) { model.closeDuplicates() }
            }
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Text(notice.text).oneLine()
                    if notice.undo != nil {
                        OButton("Undo", icon: "arrow.uturn.backward", size: .small) { model.undoRemove() }
                    }
                }
            }
        }
        .font(Theme.body(13.5))
        .foregroundStyle(Theme.inkMuted)
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
            .keepInside(CGPoint(x: dragged.location.x - dragged.grab.width,
                                y: dragged.location.y - dragged.grab.height))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var ghost: some View {
        if let dragged = model.drag {
            SortRowFace(item: dragged.item, closing: dragged.closing)
                .padding(.leading, 5).padding(.trailing, 8)
                .frame(width: 168, height: SortMetrics.rowHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(Theme.surfaceRaised)
                    .elevation(.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)))
                .keepInside(CGPoint(x: dragged.location.x - dragged.grab.width,
                                y: dragged.location.y - dragged.grab.height))
                .allowsHitTesting(false)
        }
    }
}
