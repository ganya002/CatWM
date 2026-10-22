import AppKit
import SwiftUI

struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject private var library = SettingsWindow.shared.library

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    private var feeling: CatFeeling {
        let status = settingsUI.status
        if !status.trusted || !status.keybindsActive { return .alert }
        return status.tilingEnabled ? .content : .sleepy
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: SettingsWindow.titlebarHeight)
            HStack(spacing: 10) {
                CatMascot(feeling: feeling).frame(height: 56).foregroundStyle(Theme.ink)
                Wordmark()
            }
            .padding(.leading, 6).padding(.bottom, 16)
            OSearchField(placeholder: "Search", text: $settingsUI.search, shortcut: ["⌘", "K"],
                         focus: searchFocused) {
                if let first = SettingsIndex.search(settingsUI.search, doc: doc).first { settingsUI.open(first) }
            }
            .background(Capsule().fill(Theme.surface))
            .padding(.bottom, 10)
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
            Spacer(minLength: 12)
            HStack(spacing: 4) {
                ConfigSelector(kind: .full, library: library)
                ConfigTransferMenu(kind: .full, library: library)
            }
            HStack(spacing: 8) {
                Text(version).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                Spacer(minLength: 0)
                FeedbackButton()
            }
            .padding(.leading, 12).padding(.top, 6)
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
    }

    private func badge(_ pane: Pane) -> SideItem.Badge? {
        switch pane {
        case .general where !(settingsUI.status.trusted && settingsUI.status.keybindsActive): .attention
        case .shortcuts where doc.problemCount > 0: .count(doc.problemCount)
        default: nil
        }
    }
}
