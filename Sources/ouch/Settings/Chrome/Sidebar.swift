import AppKit
import SwiftUI

struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject private var library = SettingsWindow.shared.library

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: SettingsWindow.titlebarHeight)
            OSearchField(placeholder: "Search settings", text: $settingsUI.search, shortcut: ["⌘", "K"],
                         focus: searchFocused) {
                if let first = SettingsIndex.search(settingsUI.search, doc: doc).first { settingsUI.open(first) }
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.surface.opacity(0.6)))
            .padding(.bottom, 14)
            VStack(spacing: 2) {
                ForEach(Pane.allCases) { pane in
                    SideItem(pane: pane, selected: pane == settingsUI.pane && settingsUI.search.isEmpty,
                             badge: badge(pane)) {
                        withAnimation(Motion.fade) {
                            settingsUI.search = ""
                            settingsUI.showMap = false
                            settingsUI.pane = pane
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

    private func badge(_ pane: Pane) -> SideItem.Badge? {
        switch pane {
        case .general where !(settingsUI.status.trusted && settingsUI.status.keybindsActive): .attention
        case .shortcuts where doc.problemCount > 0: .count(doc.problemCount)
        default: nil
        }
    }
}
