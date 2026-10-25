import AppKit
import SwiftUI

struct SortClosedHeader: View {
    @ObservedObject var model: SortModel
    let group: SortClosedLane
    @StateObject private var hover = Flag()

    var body: some View {
        HStack(spacing: 8) {
            Text(group.number).font(Theme.display(15)).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
            Text(group.name.isEmpty ? "Workspace \(group.number)" : group.name).font(Theme.body(13.5, .medium))
                .foregroundStyle(Theme.inkMuted).strikethrough(true, color: Theme.danger).oneLine()
            Spacer(minLength: 0)
            Text(group.ids.isEmpty ? "" : "\(group.ids.count)")
                .textStyle(.caption).monospacedDigit().foregroundStyle(Theme.inkFaint).fixedSize()
        }
        .padding(.leading, 5).padding(.trailing, 8)
        .frame(height: SortMetrics.rowHeight)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .fill(hover.isOn ? Theme.hover : .clear))
        .overlay(alignment: .trailing) {
            if hover.isOn {
                RemoveButton(help: "Bring back", variant: .restore, tooltip: false) { model.reopen(group.id) }
                    .padding(.trailing, 2)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.hover))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.isOn = $0 }
        .onTapGesture { model.reopen(group.id) }
        .accessibilityLabel("Closed workspace \(group.number), \(group.ids.count) windows")
        .accessibilityAddTraits(.isButton)
    }
}
