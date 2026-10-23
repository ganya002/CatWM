import AppKit
import SwiftUI

struct SortLaneView: View {
    @ObservedObject var model: SortModel
    let index: Int
    let lane: SortLane
    let rows: Int
    @StateObject private var hover = Flag()
    @FocusState private var editing: Bool
    @StateObject private var number = NumberEdit()
    @FocusState private var numberFocus: Bool

    private var carry: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
            .onChanged { model.columnDragChanged(lane, $0) }
            .onEnded { _ in model.columnDragEnded() }
    }

    @ViewBuilder private func numberView(filled: Bool) -> some View {
        if number.isEditing {
            TextField("", text: $number.draft)
                .textFieldStyle(.plain).font(Theme.display(22)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(Theme.ink)
                .frame(width: 32)
                .focused($numberFocus)
                .onChange(of: number.draft) { _, draft in
                    let digits = String(draft.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if digits != draft { number.draft = digits }
                }
                .onSubmit { numberFocus = false }
                .onChange(of: numberFocus) { _, focused in if !focused { commitNumber() } }
                .accessibilityLabel("Number for workspace \(lane.number)")
        } else {
            Text(lane.number).font(Theme.display(22)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(filled ? Theme.ink : Theme.inkFaint).fixedSize()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.finish(lane.workspace) }
                .onTapGesture {
                    number.draft = lane.number
                    number.isEditing = true
                    DispatchQueue.main.async { numberFocus = true }
                }
                .gesture(carry)
                .tooltip("Click to change the number, double-click to go to workspace \(lane.number)")
        }
    }

    private func lead(of id: CGWindowID) -> CGWindowID? { model.plan.tabs(of: id).first(where: lane.ids.contains) }

    private func commitNumber() {
        guard number.isEditing else { return }
        number.isEditing = false
        withAnimation(Motion.spring) { model.renumber(lane.id, to: number.draft) }
    }

    var body: some View {
        let over = model.over == .lane(lane.id)
        let count = lane.ids.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                numberView(filled: count > 0)
                TextField("", text: Binding(get: { lane.name }, set: { model.rename(lane.id, $0) }),
                          prompt: Text("Workspace \(lane.number)").foregroundStyle(Theme.inkFaint))
                    .textFieldStyle(.plain).font(Theme.heading())
                    .foregroundStyle(Theme.ink)
                    .focused($editing)
                    .onSubmit { editing = false }
                    .accessibilityLabel("Name for workspace \(lane.number)")
                Text(count > 0 ? "\(count)" : "")
                    .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
                    .gesture(carry)
                if model.plan.lanes.count > 1 {
                    RemoveButton(help: "Remove workspace \(lane.number)", variant: .close) {
                        withAnimation(Motion.easeOut) { model.removeLane(index) }
                    }
                        .opacity(hover.isOn || editing ? 1 : 0)
                        .padding(.vertical, -4)
                }
            }
            .padding(.horizontal, 4)
            SortThumb(layout: lane.layout, ids: model.plan.tiles(lane.ids),
                      lit: (model.hover ?? model.selected).flatMap(lead),
                      ratio: model.plan.geometry[lane.workspace]?.ratio ?? 0.5,
                      mainCount: model.plan.geometry[lane.workspace]?.mainCount ?? 1)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.finish(lane.workspace) }
                .gesture(carry)
                .tooltip("Double-click to go to workspace \(lane.number)")
            SortLayoutPill(layout: lane.layout,
                           next: { model.cycleLayout(of: index) },
                           previous: { model.cycleLayout(of: index, by: -1) })
                .padding(.leading, 4)
            SortList(model: model, ids: lane.ids, closing: false, rows: rows)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(over ? Theme.accentSoft : Theme.surfaceRaised))
        .opacity(model.columnDrag?.lane.id == lane.id ? 0.3 : 1)
        .overlay(alignment: .leading) { slotBar(model.columnSlot == index).offset(x: -3.5) }
        .overlay(alignment: .trailing) {
            slotBar(model.columnSlot == index + 1 && index == model.plan.lanes.count - 1).offset(x: 3.5)
        }
        .animation(Motion.fadeMedium, value: over)
        .animation(Motion.fade, value: model.columnSlot)
        .zone(.lane(lane.id))
        .onHover { hover.isOn = $0 }
        .onChange(of: model.focusName) { _, id in
            if id == lane.id { editing = true; model.focusName = nil }
        }
    }
}
