import AppKit
import SwiftUI

struct SortAddLane: View {
    @ObservedObject var model: SortModel
    let plan: SortPlan
    let rows: Int
    @StateObject private var hover = Flag()

    var body: some View {
        let next = model.nextName
        let full = next == nil
        let drop = model.over == .add
        let over = drop || (hover.isOn && !full)
        let box = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Motion.easeOut) { _ = model.addLane(focus: true) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("+").font(Theme.display(22)).fixedSize()
                        Text(title(next)).font(Theme.heading()).oneLine()
                    }
                    .foregroundStyle(hover.isOn && !full ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 4)
                    ZStack {
                        box.fill(drop ? Theme.accentSoft : .clear)
                        box.strokeBorder(over ? Theme.accent : Theme.borderControl,
                                         style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(over ? 1 : 0.6)
                        if drop {
                            Image(systemName: "plus").font(Theme.symbol(Theme.Icon.extraLarge, .regular))
                                .foregroundStyle(Theme.accentInk)
                        }
                    }
                    .aspectRatio(16 / 10, contentMode: .fit)
                        .padding(.horizontal, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(full)
            .onHover { hover.isOn = $0 }
            .accessibilityLabel("Add workspace \(next ?? "")")
            SortLayoutPill(layout: model.nextLayout,
                           next: { model.cycleNextLayout() },
                           previous: { model.cycleNextLayout(by: -1) })
                .padding(.leading, 4)
            Color.clear.frame(height: CGFloat(rows) * SortMetrics.rowHeight)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(over ? Theme.accentSoft : .clear))
        .overlay {
            if drop {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .opacity(full ? 0.45 : 1)
        .animation(Motion.fadeMedium, value: over)
        .zone(.add)
    }

    private func title(_ next: String?) -> String {
        next.map { "Workspace \($0)" }
            ?? (plan.lanes.count >= SortPlan.maxLanes ? "All \(SortPlan.maxLanes) in use" : "None free")
    }
}
