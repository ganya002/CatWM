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
        if number.on {
            TextField("", text: $number.draft)
                .textFieldStyle(.plain).font(Theme.display(22)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(Theme.accentInk)
                .frame(width: 32)
                .focused($numberFocus)
                .onChange(of: number.draft) { _, v in
                    let digits = String(v.filter { $0.isASCII && $0.isNumber }.prefix(2))
                    if digits != v { number.draft = digits }
                }
                .onSubmit { numberFocus = false }
                .onChange(of: numberFocus) { _, on in if !on { commitNumber() } }
                .accessibilityLabel("Number for workspace \(lane.ws)")
        } else {
            Text(lane.ws).font(Theme.display(22)).monospacedDigit().tracking(-0.4)
                .foregroundStyle(filled ? Theme.accentInk : Theme.inkFaint).fixedSize()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.finish(lane.ws) }
                .onTapGesture {
                    number.draft = lane.ws
                    number.on = true
                    DispatchQueue.main.async { numberFocus = true }
                }
                .gesture(carry)
                .tooltip("Click to change the number, double-click to go to workspace \(lane.ws)")
        }
    }

    private func commitNumber() {
        guard number.on else { return }
        number.on = false
        withAnimation(Motion.spring) { model.renumber(lane.id, to: number.draft) }
    }

    var body: some View {
        let over = model.over == .lane(lane.id)
        let n = lane.ids.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                numberView(filled: n > 0)
                TextField("", text: Binding(get: { lane.name }, set: { model.rename(lane.id, $0) }),
                          prompt: Text("Workspace \(lane.ws)").foregroundStyle(Theme.inkFaint))
                    .textFieldStyle(.plain).font(Theme.heading()).foregroundStyle(editing ? Theme.accentInk : Theme.ink)
                    .focused($editing)
                    .onSubmit { editing = false }
                    .accessibilityLabel("Name for workspace \(lane.ws)")
                Text(n > 0 ? "\(n)" : "").textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
                    .gesture(carry)
                if model.plan.lanes.count > 1 {
                    RemoveButton(help: "Remove workspace \(lane.ws)", variant: .close) { withAnimation(Motion.easeOut) { model.removeLane(index) } }
                        .opacity(hover.on || editing ? 1 : 0)
                        .padding(.vertical, -4)
                }
            }
            .padding(.horizontal, 4)
            SortThumb(layout: lane.layout, ids: lane.ids, lit: model.hover ?? model.selected,
                      ratio: model.plan.geometry[lane.ws]?.ratio ?? 0.5, mainCount: model.plan.geometry[lane.ws]?.mainCount ?? 1)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.finish(lane.ws) }
                .gesture(carry)
                .tooltip("Double-click to go to workspace \(lane.ws)")
            SortLayoutPill(layout: lane.layout, next: { model.cycleLayout(of: index) }, previous: { model.cycleLayout(of: index, by: -1) })
                .padding(.leading, 4)
            SortList(model: model, ids: lane.ids, closing: false, rows: rows)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(over ? Theme.accentSoft : .clear))
        .opacity(model.columnDrag?.lane.id == lane.id ? 0.3 : 1)
        .overlay(alignment: .leading) { slotBar(model.columnSlot == index).offset(x: -3.5) }
        .overlay(alignment: .trailing) { slotBar(model.columnSlot == index + 1 && index == model.plan.lanes.count - 1).offset(x: 3.5) }
        .animation(Motion.fadeMedium, value: over)
        .animation(Motion.fade, value: model.columnSlot)
        .zone(.lane(lane.id))
        .onHover { hover.on = $0 }
        .onChange(of: model.focusName) { _, id in
            if id == lane.id { editing = true; model.focusName = nil }
        }
    }
}
