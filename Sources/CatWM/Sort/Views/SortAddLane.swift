import AppKit
import CatWMKit
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
        let hovered = hover.isOn && !full
        let box = RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(Motion.user) { _ = model.addLane(focus: true) } } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("+").textStyle(.title).fixedSize()
                        Text(title(next)).textStyle(.sectionTitle).oneLine()
                    }
                    .foregroundStyle(hovered ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 4)
                    ZStack {
                        box.fill(drop ? Theme.accentSoft : .clear)
                        box.strokeBorder(drop ? Theme.accent : Theme.borderControl,
                                         style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .opacity(drop || hovered ? 1 : 0.6)
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
            .accessibilityLabel("Add workspace \(next.map { WorkspaceKey.number($0) } ?? "")")
            SortLayoutPill(layout: model.nextLayout,
                           next: { model.cycleNextLayout() },
                           previous: { model.cycleNextLayout(by: -1) })
                .padding(.leading, 4)
            Color.clear.frame(height: CGFloat(rows) * SortMetrics.rowHeight)
        }
        .padding(.vertical, 8).padding(.horizontal, 4)
        .frame(width: SortMetrics.lane, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(drop ? Theme.accentSoft : hovered ? Theme.hover : .clear))
        .overlay {
            if drop {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            }
        }
        .opacity(full ? 0.45 : 1)
        .animation(Motion.fadeMedium, value: drop || hovered)
        .zone(.add)
    }

    private func title(_ next: String?) -> String {
        next.map { "Workspace \(WorkspaceKey.number($0))" }
            ?? (plan.lanes.count >= SortPlan.maxLanes ? "All \(SortPlan.maxLanes) in use" : "None free")
    }
}
