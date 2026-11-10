import AppKit
import CatWMKit
import SwiftUI

struct SortView: View {
    @ObservedObject var model: SortModel
    let width: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static var inset: EdgeInsets {
        EdgeInsets(top: Elevation.float.room, leading: Elevation.float.room, bottom: 0, trailing: Elevation.float.room)
    }

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.xxl, topTrailingRadius: Theme.Radius.xxl,
                               style: .continuous)
    }

    var body: some View {
        let plan = model.plan
        let closeCount = CGFloat(plan.closeRowCount)
        let closeRows = Int(ceil(closeCount - SortMetrics.closeExtra / SortMetrics.rowHeight))
        let tallest = ([closeRows] + plan.lanes.map(plan.rowCount)).max() ?? 1
        let rows = min(model.maxRows, max(SortMetrics.minRows, tallest))
        VStack(alignment: .leading, spacing: 0) {
            let hasHeader = model.displays.count > 1 || plan.duplicateText != nil || model.notice != nil
            if hasHeader { header(plan) }
            HStack(alignment: .top, spacing: 4) {
                row(plan, rows: rows)
                closedColumn(plan, rows: rows)
            }
            .overlay(alignment: .trailing) { dropZone }
            .animation(Motion.user(reduceMotion: reduceMotion), value: model.carriesToClose)
            .animation(Motion.user(reduceMotion: reduceMotion),
                       value: plan.close.isEmpty && plan.closedLanes.isEmpty)
            .padding(.top, hasHeader ? Theme.Space.small : 0).padding(.horizontal, -8)
            actions
        }
        .frame(width: width - 40)
        .padding(Density.large.padding)
        .padding(.top, Theme.Space.small)
        .background { Self.shape.fill(Theme.surface).elevation(.float, in: Self.shape) }
        .zone(.panel)
        .panelEntrance(model.shown, style: model.motion)
        .padding(Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "sort")
        .onPreferenceChange(SortZoneKey.self) { model.zones = $0 }
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
    }

    private func header(_ plan: SortPlan) -> some View {
        HStack(spacing: 12) {
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
                withAnimation(Motion.user) { proxy.scrollTo(lane) }
            }
        }
    }

    private func unplacedFullscreen(_ plan: SortPlan) -> [SortItem] {
        (model.currentDisplay?.fullscreen ?? []).filter { plan.items[$0.id] == nil }
    }

    @ViewBuilder private func closedColumn(_ plan: SortPlan, rows: Int) -> some View {
        let count = plan.close.count
        if count > 0 || !plan.closedLanes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Closed").font(Theme.heading()).foregroundStyle(Theme.inkMuted).oneLine()
                    Text(count > 0 ? "\(count)" : "")
                        .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
                }
                .padding(.horizontal, 4)
                SortCloseList(model: model, plan: plan, rows: rows)
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(width: SortMetrics.lane, alignment: .topLeading)
            .padding(.leading, 4).padding(.trailing, 8)
            .transition(.asymmetric(insertion: .identity, removal: .opacity.combined(with: .offset(x: 24))))
        }
    }

    @ViewBuilder private var dropZone: some View {
        if model.carriesToClose {
            let over = model.over == .close
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            Text("Drop to close").font(Theme.heading()).foregroundStyle(Theme.danger).oneLine()
                .frame(width: SortMetrics.lane)
                .frame(maxHeight: .infinity)
                .background {
                    shape.fill(Theme.surface).elevation(.popover, in: shape, outlined: false)
                    shape.fill(Theme.dangerSoft).opacity(over ? 1 : 0.6)
                }
                .animation(Motion.fadeMedium, value: over)
                .zone(.close)
                .padding(.trailing, 8).padding(.bottom, 6)
                .transition(.opacity.combined(with: .offset(x: 24)))
                .accessibilityLabel("Drop to close")
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            OButton("Revert", variant: .ghost, size: .small, shortcut: ["esc"]) { model.revert() }
            OButton("Done", variant: .primary, size: .small, shortcut: ["⏎"]) { model.finish(nil) }
        }
        .font(Theme.body(13.5))
        .padding(.top, SortMetrics.closeGap)
    }

    private func notices(_ plan: SortPlan) -> some View {
        HStack(spacing: 8) {
            if let text = plan.duplicateText {
                OButton(text, icon: "xmark.circle", variant: .ghost) { model.closeDuplicates() }
            }
            if let notice = model.notice { Text(notice.text).oneLine() }
        }
        .font(Theme.body(13.5))
        .foregroundStyle(Theme.inkMuted)
    }
}
