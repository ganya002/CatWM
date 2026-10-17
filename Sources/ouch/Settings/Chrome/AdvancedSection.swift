import AppKit
import SwiftUI

struct AdvancedSection<Content: View>: View {
    let pane: Pane
    @ObservedObject var ui: SettingsUI
    @ViewBuilder var content: Content

    var body: some View {
        let open = ui.advancedOpen.contains(pane)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.easeOut) {
                    if open { ui.advancedOpen.remove(pane) } else { ui.advancedOpen.insert(pane) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced").textStyle(.sectionTitle)
                    Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.xs, .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 6)
                }
                .foregroundStyle(open ? Theme.accentInk : Theme.inkMuted)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide advanced settings" : "Show advanced settings")
            if open {
                VStack(alignment: .leading, spacing: 30) { content }
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
