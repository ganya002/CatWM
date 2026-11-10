import AppKit
import CatWMKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @ObservedObject private var templates = TemplateLibrary.shared
    @ObservedObject private var feedback = Feedback.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(doc: doc, settingsUI: settingsUI, searchFocused: $searchFocused)
                .frame(width: 196)
            PaneHost(doc: doc, settingsUI: settingsUI)
                .pane(shadow: false)
                .padding(EdgeInsets(top: Theme.Space.small, leading: 0,
                                    bottom: Theme.Space.small, trailing: Theme.Space.small))
        }
        .sheet(item: $templates.draft) { TemplateSheet(template: $0, library: templates) }
        .sheet(isPresented: $feedback.isOpen) { FeedbackSheet(feedback: feedback) }
        .background(Theme.wash.ignoresSafeArea())
        .overlayPreferenceValue(TipAnchorKey.self) { SettingsTipLayer(anchors: $0) }
        .onChange(of: settingsUI.pane) { _, pane in Tips.shared.paneShown(pane) }
        .onChange(of: [doc.config.paddingTop, doc.config.paddingBottom,
                       doc.config.paddingLeft, doc.config.paddingRight]) { _, paddings in
            if Set(paddings).count > 1 { settingsUI.linkedPadding = false }
        }
        .ignoresSafeArea()
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("k").hidden()
        }
        .sheet(item: $library.sheet) { ConfigSheetView(sheet: $0, library: library) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { library.importFile(url) } }
            }
            return true
        }
    }
}
