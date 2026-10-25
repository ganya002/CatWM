import AppKit
import SwiftUI

struct AdvancedSection<Content: View>: View {
    let pane: Pane
    @ObservedObject var settingsUI: SettingsUI
    @ViewBuilder var content: Content

    var body: some View {
        let open = settingsUI.advancedOpen.contains(pane)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.easeOut) {
                    if open { settingsUI.advancedOpen.remove(pane) } else { settingsUI.advancedOpen.insert(pane) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Advanced").textStyle(.sectionTitle)
                    Image(systemName: "chevron.right").font(Theme.symbol(Theme.Icon.extraSmall, .bold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 6)
                }
                .foregroundStyle(open ? Theme.ink : Theme.inkMuted)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(open ? "Hide advanced settings" : "Show advanced settings")
            if open {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) { content }
                    .padding(.top, Theme.Space.small)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
