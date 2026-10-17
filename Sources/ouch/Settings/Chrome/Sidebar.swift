import AppKit
import SwiftUI

struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject private var library = SettingsWindow.shared.library

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SettingsWindow.titlebarHeight)
            OSearchField(placeholder: "Search settings", text: $ui.search, shortcut: ["⌘", "K"], focus: searchFocused) {
                if let first = SettingsIndex.search(ui.search, doc: doc).first { ui.open(first) }
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.surface.opacity(0.6)))
            .padding(.bottom, 14)
            VStack(spacing: 2) {
                ForEach(Pane.allCases) { p in
                    SideItem(pane: p, on: p == ui.pane && ui.search.isEmpty, badge: badge(p)) {
                        withAnimation(Motion.fade) {
                            ui.search = ""
                            ui.showMap = false
                            ui.pane = p
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 8) {
                OSectionHeader("Config", tone: Theme.inkMuted).padding(.leading, 10)
                HStack(spacing: 4) {
                    ConfigSelector(kind: .full, library: library)
                    ConfigTransferMenu(kind: .full, library: library)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Wordmark()
                    Text(version).font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 0)
                    FeedbackButton()
                }
                .padding(.leading, 10).padding(.top, 6)
            }
        }
        .padding(.leading, 10).padding(.trailing, 6).padding(.bottom, 12)
    }

    private func badge(_ p: Pane) -> SideItem.Badge? {
        switch p {
        case .general where !(ui.status.trusted && ui.status.keybindsActive): .attention
        case .shortcuts where doc.problemCount > 0: .count(doc.problemCount)
        default: nil
        }
    }
}
