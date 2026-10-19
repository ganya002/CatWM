import AppKit
import SwiftUI

struct ResultRow: View {
    let entry: SettingEntry
    let first: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.bind != nil ? "command" : entry.pane.icon)
                    .font(Theme.symbol()).foregroundStyle(Theme.accentInk).frame(width: 18)
                Text(entry.title).font(Theme.body(14)).oneLine()
                if entry.advanced {
                    Text("Advanced").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
                Spacer(minLength: 8)
                if first { Text("↩").font(Theme.keys(12)).foregroundStyle(Theme.inkMuted) }
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.small, .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .opacity(hover.isOn ? 1 : 0)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(hover.isOn ? Theme.well : .clear))
            .padding(.horizontal, -10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.isOn = $0 }
    }
}
