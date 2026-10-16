// Sort: the Sort panel's SwiftUI views (columns, rows, drag, header, footer).
import AppKit
import SwiftUI

// The Sort panel's views: a Surface `lg` on glass with the header, a row of workspace columns, the Close
// column pinned at the right, and the footer. Rows are menu rows; dragging is done by hand so the dragged
// row can follow the pointer with a popover shadow and nothing else.

private extension View {
    /// Reports this view's frame in the panel's coordinate space, for hit-testing drops.
    func zone(_ z: SortZone) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: SortZoneKey.self, value: [z: g.frame(in: .named("sort"))])
        })
    }
}

private struct SortZoneKey: PreferenceKey {
    static var defaultValue: [SortZone: CGRect] = [:]
    static func reduce(value: inout [SortZone: CGRect], nextValue: () -> [SortZone: CGRect]) { value.merge(nextValue()) { $1 } }
}

private enum SortMetrics {
    static let lane: CGFloat = 176
    static let rowHeight = Theme.rowHeight
}

struct SortView: View {
    @ObservedObject var model: SortModel
    /// Width of the surface, padding included.
    let width: CGFloat
    /// Transparent room around the surface for its float shadow, which would be clipped at the panel edge.
    static let inset = EdgeInsets(top: 24, leading: 48, bottom: 64, trailing: 48)

    var body: some View {
        let plan = model.plan
        let rows = min(model.maxRows, max(1, ([plan.close.count + plan.closedLanes.count] + plan.lanes.map(\.ids.count)).max() ?? 1))
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

    // MARK: Header

    private func header(_ plan: SortPlan) -> some View {
        let n = plan.items.count
        return HStack(spacing: 12) {
            (Text("Sort ").font(Theme.body(22))
                + Text("\(n)").font(Theme.body(22, .medium)).foregroundColor(Theme.accentInk)
                + Text(n == 1 ? " window" : " windows").font(Theme.body(22)))
                .tracking(-0.2).oneLine().fixedSize()
            if model.displays.count > 1 { SortDisplays(model: model) }
            Spacer(minLength: 12)
            SortStrategies(selection: plan.strategy) { model.pick($0) }
        }
        .padding(.bottom, 4)
    }

    // MARK: Lanes

    private func row(_ plan: SortPlan, rows: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach(Array(plan.lanes.enumerated()), id: \.element.id) { i, lane in
                        SortLaneView(model: model, index: i, lane: lane, rows: rows).id(lane.id)
                            .tileItem(model.shown, style: model.motion,
                                      spread: CGSize(width: -CGFloat(i) * (SortMetrics.lane + 4), height: 0))
                    }
                    SortAddLane(model: model, plan: plan)
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

    /// Shaped like a workspace column so its rows line up: header, a drop box where the thumbnail sits,
    /// an empty slot for the layout pill, then the windows that close when the panel is done.
    private func closeLane(_ plan: SortPlan, rows: Int) -> some View {
        let over = model.over == .close
        let n = plan.close.count
        let box = RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Image(systemName: "xmark")).font(Theme.display(22)).foregroundStyle(Theme.danger).fixedSize()
                Text("Close").font(Theme.heading()).foregroundStyle(Theme.ink).oneLine()
                Text(n > 0 ? "\(n)" : "").font(Theme.body(12)).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
            }
            .padding(.horizontal, 4)
            ZStack {
                box.fill(over || n > 0 ? Theme.dangerSoft : .clear)
                if !(over || n > 0) {
                    box.strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).opacity(0.5)
                }
                Image(systemName: "xmark.circle").font(.system(size: 20, weight: .regular))
                    .foregroundStyle(over || n > 0 ? Theme.danger : Theme.inkFaint)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .padding(.horizontal, 4)
            .animation(.easeOut(duration: Theme.medium), value: over)
            Color.clear.frame(height: 24)
            SortCloseList(model: model, plan: plan, rows: rows)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.hairline).frame(width: 1).padding(.vertical, 6).offset(x: -4) }
        .zone(.close)
        .padding(.leading, 4).padding(.trailing, 8)
    }

    // MARK: Footer

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

    // MARK: Drag

    @ViewBuilder private var columnGhost: some View {
        if let d = model.columnDrag {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d.lane.ws).font(Theme.display(22)).monospacedDigit().tracking(-0.4).foregroundStyle(Theme.accentInk).fixedSize()
                    Text(d.lane.name.isEmpty ? "Workspace \(d.lane.ws)" : d.lane.name).font(Theme.heading()).oneLine()
                }
                .padding(.horizontal, 4)
                SortThumb(layout: d.lane.layout, ids: d.lane.ids, lit: nil, ratio: d.ratio, mainCount: d.mainCount).padding(.horizontal, 4)
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(width: SortMetrics.lane, alignment: .topLeading)
            .background(shape.fill(Theme.surfaceRaised).elevation(.popover, in: shape))
            .offset(x: d.location.x - d.grab.width, y: d.location.y - d.grab.height)
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
                .offset(x: d.location.x - d.grab.width, y: d.location.y - d.grab.height)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Header controls

/// A segmented control like `OSegmented`, with room for nothing being selected.
private struct SortStrategies: View {
    let selection: SortStrategy?
    let pick: (SortStrategy) -> Void
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SortStrategy.allCases, id: \.self) { s in
                let on = s == selection
                Button { withAnimation(Motion.spring) { pick(s) } } label: {
                    Text(s.title).font(Theme.body(12.5, on ? .medium : .regular)).oneLine()
                        .foregroundStyle(on ? Theme.onAccent : Theme.inkMuted)
                        .padding(.horizontal, 12).frame(height: 24)
                        .background { if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group by")
    }
}

/// Which display is being sorted. A window dropped on one moves to the workspace that display is showing.
private struct SortDisplays: View {
    @ObservedObject var model: SortModel
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.displays) { d in
                let on = d.id == model.current
                let over = model.over == .display(d.id) && !on
                Button { withAnimation(Motion.spring) { model.use(d.id) } } label: {
                    HStack(spacing: 7) {
                        SortScreenGlyph(display: d, color: on ? Theme.onAccent : over ? Theme.accentInk : Theme.inkMuted)
                        Text(d.short).font(Theme.body(12.5, on ? .medium : .regular)).oneLine()
                        Text("\(model.count(of: d.id))").font(Theme.body(12)).monospacedDigit()
                            .foregroundStyle(on ? Theme.onAccent.opacity(0.8) : Theme.inkFaint)
                    }
                    .foregroundStyle(on ? Theme.onAccent : over ? Theme.accentInk : Theme.inkMuted)
                    .padding(.leading, 9).padding(.trailing, 12).frame(height: 24)
                    .background {
                        if on { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) }
                        else if over { Capsule().fill(Theme.accentSoft) }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .zone(.display(d.id))
                .tooltip(d.name)
                .accessibilityLabel(d.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.well))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Display to sort")
    }
}

private struct SortScreenGlyph: View {
    let display: SortDisplay
    let color: Color

    var body: some View {
        let w = min(24, max(16, (12 * display.aspect).rounded()))
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(color, lineWidth: 1.5).frame(width: w, height: 12)
            Capsule().fill(color).frame(width: display.isLaptop ? w + 5 : 6, height: 1.5)
        }
        .frame(height: 16)
    }
}

// MARK: - Lanes

/// The state of typing over a workspace number, in an object rather than @State (the Command Line Tools ship
/// without SwiftUI's macro plugin).
private final class NumberEdit: ObservableObject {
    @Published var on = false
    @Published var draft = ""
}

private struct SortLaneView: View {
    @ObservedObject var model: SortModel
    let index: Int
    let lane: SortLane
    let rows: Int
    @StateObject private var hover = Flag()
    @FocusState private var editing: Bool
    @StateObject private var number = NumberEdit()
    @FocusState private var numberFocus: Bool

    /// Dragging the number, the count or the thumbnail carries the whole workspace: to Close, onto another
    /// workspace to merge the two, or to the edge of one to move it there.
    private var carry: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
            .onChanged { model.columnDragChanged(lane, $0) }
            .onEnded { _ in model.columnDragEnded() }
    }

    /// The workspace number. Dragging carries the workspace and a double-click goes to it; a single click
    /// (the double-click gets its chance first) types a new number, which `commitNumber` applies.
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
                Text(n > 0 ? "\(n)" : "").font(Theme.body(12)).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
                    .gesture(carry)
                if model.plan.lanes.count > 1 {
                    SortRemoveButton(label: "Remove workspace \(lane.ws)") { withAnimation(Motion.easeOut) { model.removeLane(index) } }
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
        .animation(.easeOut(duration: Theme.medium), value: over)
        .animation(.easeOut(duration: Theme.fast), value: model.columnSlot)
        .zone(.lane(lane.id))
        .onHover { hover.on = $0 }
        .onChange(of: model.focusName) { _, id in
            if id == lane.id { editing = true; model.focusName = nil }
        }
    }
}

/// Where a carried workspace would go: a bar in the gap before (or after) a column.
private func slotBar(_ on: Bool) -> some View {
    Capsule().fill(Theme.accent).frame(width: 3).padding(.vertical, 6).opacity(on ? 1 : 0).allowsHitTesting(false)
}

private struct SortRemoveButton: View {
    let label: String
    /// The × that removes or closes; `false` is the plain affordance that brings something back.
    var removes = true
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            Image(systemName: removes ? "xmark" : "arrow.uturn.backward").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hover.on && removes ? Theme.danger : hover.on ? Theme.ink : Theme.inkMuted)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(hover.on ? (removes ? Theme.dangerSoft : Theme.hover) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.fast), value: hover.on)
        .tooltip(label)
        .accessibilityLabel(label)
    }
}

/// The column after the last workspace: same size, an empty preview, and the layout new ones start with.
private struct SortAddLane: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    @StateObject private var hover = Flag()

    var body: some View {
        let next = model.nextName
        let full = next == nil
        let over = model.over == .add || (hover.on && !full)
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Motion.easeOut) { _ = model.addLane(focus: true) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("+").font(Theme.display(22)).fixedSize()
                        Text(next.map { "Workspace \($0)" } ?? (plan.lanes.count >= SortPlan.maxLanes ? "All \(SortPlan.maxLanes) in use" : "None free"))
                            .font(Theme.heading()).oneLine()
                    }
                    .foregroundStyle(hover.on && !full ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 4)
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(over ? Theme.accent : Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .opacity(over ? 1 : 0.6)
                        .aspectRatio(16 / 10, contentMode: .fit)
                        .padding(.horizontal, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(full)
            .onHover { hover.on = $0 }
            .accessibilityLabel("Add workspace \(next ?? "")")
            SortLayoutPill(layout: model.nextLayout, next: { model.cycleNextLayout() }, previous: { model.cycleNextLayout(by: -1) })
                .padding(.leading, 4)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(over ? Theme.accentSoft : .clear))
        .opacity(full ? 0.45 : 1)
        .animation(.easeOut(duration: Theme.medium), value: over)
        .zone(.add)
    }
}

/// Click for the next layout, right-click for the previous one.
private struct SortLayoutPill: View {
    let layout: Layout
    let next: () -> Void
    let previous: () -> Void
    @StateObject private var hover = Flag()
    private let help = "Click for next layout, right-click for previous"

    var body: some View {
        Button(action: next) {
            HStack(spacing: 6) {
                SortLayoutGlyph(layout: layout).frame(width: 16, height: 14)
                Text(layout == .bsp ? "BSP" : layout.title).font(Theme.body(12)).oneLine()
            }
            .foregroundStyle(hover.on ? Theme.ink : Theme.inkMuted)
            .padding(.leading, 7).padding(.trailing, 10).frame(height: 24)
            .background(Capsule().fill(hover.on ? Theme.wellHover : Theme.well))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .overlay(SortRightClick(action: previous))
        .onHover { hover.on = $0 }
        .animation(.easeOut(duration: Theme.fast), value: hover.on)
        .tooltip(help)
        .accessibilityLabel("Layout: \(layout.title)")
        .accessibilityAction(named: "Previous layout", previous)
    }
}

/// A layout drawn small, in the current text colour.
private struct SortLayoutGlyph: View {
    let layout: Layout

    var body: some View {
        GeometryReader { g in
            let r = CGRect(origin: .zero, size: g.size).insetBy(dx: 1, dy: 0.5)
            let count = layout == .fullscreen ? 1 : layout == .bsp ? 4 : layout == .twoPane || layout == .twoPaneRight ? 2 : 3
            let frames = layout.frames(count: count, in: r.insetBy(dx: -0.75, dy: -0.75), ratio: 0.5, mainCount: 1)?
                .map { $0.insetBy(dx: 0.75, dy: 0.75) }
                ?? [CGRect(x: 1, y: 1, width: 9, height: 8), CGRect(x: 5, y: 4, width: 10, height: 9)]
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { _, f in
                    RoundedRectangle(cornerRadius: 1.4, style: .continuous).frame(width: f.width, height: f.height).offset(x: f.minX, y: f.minY)
                }
            }
        }
        .opacity(0.8)
        .accessibilityHidden(true)
    }
}

/// The workspace as it will tile, drawn with the real layout maths. The window under the pointer is yellow.
private struct SortThumb: View {
    let layout: Layout
    let ids: [CGWindowID]
    let lit: CGWindowID?
    var ratio: CGFloat = 0.5
    var mainCount = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let frames = Self.frames(layout, ids.count, g.size, ratio: ratio, mainCount: mainCount)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.well)
                ForEach(Array(ids.enumerated()), id: \.element) { j, id in
                    if j < frames.count {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(id == lit ? Theme.accent : j == 0 ? Theme.thumbMain : Theme.tint)
                            .frame(width: frames[j].width, height: frames[j].height)
                            .offset(x: frames[j].minX, y: frames[j].minY)
                    }
                }
            }
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .animation(Motion.snap(reduceMotion), value: layout)
        .animation(Motion.snap(reduceMotion), value: ids)
        .accessibilityHidden(true)
    }

    static func frames(_ layout: Layout, _ n: Int, _ size: CGSize, ratio: CGFloat, mainCount: Int) -> [CGRect] {
        guard n > 0 else { return [] }
        let k = size.width / 140
        let inset = 4 * k, gap = 3 * k
        let r = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        if layout == .fullscreen { // stacked, each a step down and to the right
            let step = 4 * k, shrink = CGFloat(min(n - 1, 6)) * step
            return (0..<n).map { CGRect(x: r.minX + CGFloat(min($0, 6)) * step, y: r.minY + CGFloat(min($0, 6)) * step,
                                        width: r.width - shrink, height: r.height - shrink) }
        }
        if let f = layout.frames(count: n, in: r.insetBy(dx: -gap / 2, dy: -gap / 2), ratio: ratio, mainCount: mainCount) {
            return f.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
        }
        return (0..<n).map { CGRect(x: r.minX + CGFloat(min($0, 6)) * 6 * k, y: r.minY + CGFloat(min($0, 6)) * 6 * k,
                                    width: r.width * 0.6, height: r.height * 0.6) }
    }
}

// MARK: - Window rows

private struct SortList: View {
    @ObservedObject var model: SortModel
    let ids: [CGWindowID]
    let closing: Bool
    let rows: Int

    var body: some View {
        let items = ids.compactMap { model.plan.items[$0] }
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: items.count > model.maxRows) {
                VStack(spacing: 0) {
                    if items.isEmpty && !closing {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                            .strokeBorder(Theme.borderControl, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(0.5).frame(height: SortMetrics.rowHeight)
                    }
                    ForEach(items) { item in SortRow(model: model, item: item, closing: closing).id(item.id) }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight)
            .onChange(of: model.reveal) { _, r in
                if ids.contains(r.id) { withAnimation(Motion.easeOut) { proxy.scrollTo(r.id) } }
            }
        }
    }
}

/// Icon, title and the app's name; the same in the list and under the pointer while dragging.
private struct SortRowFace: View {
    let item: SortItem
    let closing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.tint)
                        .overlay(Text(String(item.app.prefix(1))).font(Theme.body(10.5, .medium)).foregroundStyle(Theme.ink))
                }
            }
            .frame(width: 20, height: 20)
            (Text(item.title).foregroundColor(closing ? Theme.inkMuted : Theme.ink)
                // The app's name only when the title doesn't already say it ("Claude  Claude").
                + Text(item.title.localizedCaseInsensitiveContains(item.app) ? "" : "  " + item.app)
                    .font(Theme.body(12)).foregroundColor(Theme.inkFaint))
                .strikethrough(closing, color: Theme.danger)
                .oneLine()
            Spacer(minLength: 0)
        }
        .font(Theme.body(13.5))
    }
}

private struct SortRow: View {
    @ObservedObject var model: SortModel
    let item: SortItem
    let closing: Bool
    /// Windows of a closed workspace sit under its header.
    var indented = false

    var body: some View {
        let pointed = model.hover == item.id
        let lit = pointed || model.selected == item.id
        SortRowFace(item: item, closing: closing)
            .padding(.leading, indented ? 19 : 5).padding(.trailing, 8)
            .frame(height: SortMetrics.rowHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(closing ? (pointed ? Theme.hover : .clear) : lit ? Theme.accentSoft : .clear))
            .overlay(alignment: .trailing) {
                // × sends the window to Close; in Close the same spot brings it back.
                if pointed && model.drag == nil {
                    SortRemoveButton(label: closing ? "Bring back" : "Close window", removes: !closing) {
                        if closing { model.restore(item.id) } else { model.markClosing(item.id) }
                    }
                    .padding(.trailing, 2)
                    .transition(.opacity)
                }
            }
            .opacity(model.drag?.id == item.id ? 0.3 : 1)
            .contentShape(Rectangle())
            .zone(.row(item.id))
            .onHover { on in
                if on { model.hover = item.id }
                else if model.hover == item.id, model.drag == nil { model.hover = nil }
            }
            .onTapGesture { if closing { model.restore(item.id) } else { model.selected = item.id } }
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("sort"))
                .onChanged { model.dragChanged(item, $0) }
                .onEnded { _ in model.dragEnded() })
            .tooltip(closing ? "Click to bring back" : "")
            .accessibilityLabel("\(item.title), \(item.app)")
    }
}

/// The Close column's rows: closed workspaces as groups (a header, then their windows), then loose windows.
private struct SortCloseList: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    let rows: Int

    var body: some View {
        let grouped = Set(plan.closedLanes.flatMap(\.ids))
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: plan.close.count + plan.closedLanes.count > model.maxRows) {
                VStack(spacing: 0) {
                    ForEach(plan.closedLanes) { g in
                        SortClosedHeader(model: model, group: g)
                        ForEach(g.ids.compactMap { plan.items[$0] }) { item in SortRow(model: model, item: item, closing: true, indented: true).id(item.id) }
                    }
                    ForEach(plan.close.filter { !grouped.contains($0) }.compactMap { plan.items[$0] }) { item in
                        SortRow(model: model, item: item, closing: true).id(item.id)
                    }
                }
            }
            .frame(height: CGFloat(rows) * SortMetrics.rowHeight)
            .onChange(of: model.reveal) { _, r in
                if plan.close.contains(r.id) || grouped.contains(r.id) { withAnimation(Motion.easeOut) { proxy.scrollTo(r.id) } }
            }
        }
    }
}

/// A closed workspace in the Close column: its number or name, how many windows, click to bring it back.
private struct SortClosedHeader: View {
    @ObservedObject var model: SortModel
    let group: SortClosedLane
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(spacing: 8) {
            Text(group.ws).font(Theme.display(15)).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
            Text(group.name.isEmpty ? "Workspace \(group.ws)" : group.name).font(Theme.body(13.5, .medium))
                .foregroundStyle(Theme.inkMuted).strikethrough(true, color: Theme.danger).oneLine()
            Spacer(minLength: 0)
            Text("\(group.ids.count)").font(Theme.body(12)).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
        }
        .padding(.leading, 5).padding(.trailing, 8)
        .frame(height: SortMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(hover.on ? Theme.hover : .clear))
        .overlay(alignment: .trailing) {
            if hover.on {
                SortRemoveButton(label: "Bring back", removes: false) { model.reopen(group.id) }
                    .padding(.trailing, 2)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.hover))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
        .onTapGesture { model.reopen(group.id) }
        .tooltip("Click to bring back")
        .accessibilityLabel("Closed workspace \(group.ws), \(group.ids.count) windows")
        .accessibilityAddTraits(.isButton)
    }
}

/// Catches only right clicks, leaving every other event to the view below.
private struct SortRightClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = RightClickView()
        v.action = action
        return v
    }

    func updateNSView(_ v: NSView, context: Context) { (v as? RightClickView)?.action = action }

    final class RightClickView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action() }
    }
}

// MARK: - Scroll access

/// Finds the scroll view around the row of workspaces, so the drag can scroll it near the edges and the
/// fade at its right end can tell whether there is more.
private struct SortScrollAccessor: NSViewRepresentable {
    let model: SortModel

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { [weak v, weak model] in model?.attach(v?.enclosingScrollView) }
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { [weak v, weak model] in
            model?.attach(v?.enclosingScrollView)
            model?.measureRow()
        }
    }
}
