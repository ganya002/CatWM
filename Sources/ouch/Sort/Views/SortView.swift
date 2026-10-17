import AppKit
import SwiftUI

struct SortView: View {
    @ObservedObject var model: SortModel
    let width: CGFloat
    static let inset = EdgeInsets(top: 24, leading: 48, bottom: 64, trailing: 48)

    var body: some View {
        let plan = model.plan
        let closeRows = Int(ceil(CGFloat(plan.close.count + plan.closedLanes.count) - SortMetrics.closeExtra / SortMetrics.rowHeight))
        let rows = min(model.maxRows, max(1, ([closeRows] + plan.lanes.map(\.ids.count)).max() ?? 1))
        VStack(alignment: .leading, spacing: 0) {
            header(plan)
            HStack(alignment: .top, spacing: 4) {
                row(plan, rows: rows)
                closeLane(plan, rows: rows)
            }
            .padding(.top, 8).padding(.horizontal, -8)
            footer(plan)
        }
        .frame(width: width - 40)
        .surface(.lg, glass: true)
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
        let n = plan.items.count
        return HStack(spacing: 12) {
            (Text("Sort ")
                + Text("\(n)").font(Theme.body(22, .medium)).foregroundColor(Theme.accentInk)
                + Text(n == 1 ? " window" : " windows"))
                .textStyle(.title).oneLine().fixedSize()
            if model.displays.count > 1 { SortDisplays(model: model) }
            Spacer(minLength: 12)
            SortStrategies(selection: plan.strategy) { model.pick($0) }
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
                }
                .padding(.horizontal, 8).padding(.bottom, 6)
                .background(SortScrollAccessor(model: model))
            }
            .zone(.scroller)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    if model.moreToRight {
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
                    }
                }
            }
            .onChange(of: model.reveal) { _, r in
                guard let lane = r.lane else { return }
                withAnimation(Motion.easeOut) { proxy.scrollTo(lane) }
            }
        }
    }

    private func closeLane(_ plan: SortPlan, rows: Int) -> some View {
        let over = model.over == .close
        let n = plan.close.count
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Image(systemName: "xmark")).font(Theme.display(22)).foregroundStyle(Theme.danger).fixedSize()
                Text("Close").font(Theme.heading()).foregroundStyle(Theme.ink).oneLine()
                Text(n > 0 ? "\(n)" : "").textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
            }
            .padding(.horizontal, 4)
            SortCloseList(model: model, plan: plan, rows: rows)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(shape.fill(over ? Theme.dangerSoft : .clear))
        .animation(Motion.fadeMedium, value: over)
        .zone(.close)
        .padding(.leading, 4).padding(.trailing, 8)
    }

    private func footer(_ plan: SortPlan) -> some View {
        HStack(spacing: 8) {
            if let text = plan.duplicateText {
                OButton(text, icon: "xmark.circle", variant: .ghost) { model.closeDuplicates() }
            }
            if let notice = model.notice {
                HStack(spacing: 8) {
                    Text(notice.text).oneLine()
                    if notice.undo != nil {
                        OButton("Undo", icon: "arrow.uturn.backward", size: .sm) { model.undoRemove() }
                    }
                }
            }
            Spacer(minLength: 8)
            OButton("Revert", variant: .ghost, shortcut: ["esc"]) { model.revert() }
            OButton("Done", variant: .primary, shortcut: ["⏎"]) { model.finish(nil) }
        }
        .font(Theme.body(13.5))
        .foregroundStyle(Theme.inkMuted)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
        .padding(.top, 4)
    }

    @ViewBuilder private var columnGhost: some View {
        if let d = model.columnDrag {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d.lane.ws).font(Theme.display(22)).monospacedDigit().tracking(-0.4).foregroundStyle(Theme.accentInk).fixedSize()
                    Text(d.lane.name.isEmpty ? "Workspace \(d.lane.ws)" : d.lane.name).font(Theme.heading()).oneLine()
                }
                .padding(.horizontal, 2)
                SortThumb(layout: d.lane.layout, ids: d.lane.ids, lit: nil, ratio: d.ratio, mainCount: d.mainCount).padding(.horizontal, 2)
            }
            .padding(.vertical, 2)
            .frame(width: SortMetrics.lane - 12, alignment: .topLeading)
            .surface(.md)
            .keepInside(CGPoint(x: d.location.x - d.grab.width, y: d.location.y - d.grab.height))
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var ghost: some View {
        if let d = model.drag {
            SortRowFace(item: d.item, closing: d.closing)
                .padding(.leading, 5).padding(.trailing, 8)
                .frame(width: 168, height: SortMetrics.rowHeight)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.surfaceRaised)
                    .elevation(.popover, in: RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)))
                .keepInside(CGPoint(x: d.location.x - d.grab.width, y: d.location.y - d.grab.height))
                .allowsHitTesting(false)
        }
    }
}
