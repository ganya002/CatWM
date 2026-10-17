import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @ObservedObject private var feedback = Feedback.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(doc: doc, ui: ui, searchFocused: $searchFocused)
                .frame(width: 228)
            PaneHost(doc: doc, ui: ui)
                .pane()
                .padding(EdgeInsets(top: Elevation.popover.room, leading: 0,
                                    bottom: Elevation.popover.room, trailing: Elevation.popover.room))
        }
        .sheet(isPresented: $feedback.isOpen) { FeedbackSheet(feedback: feedback) }
        .background(Theme.wash.ignoresSafeArea())
        .overlayPreferenceValue(TipAnchorKey.self) { SettingsTipLayer(anchors: $0) }
        .onChange(of: ui.pane) { _, p in Tips.shared.paneShown(p) }
        .onChange(of: [doc.config.paddingTop, doc.config.paddingBottom, doc.config.paddingLeft, doc.config.paddingRight]) { _, p in
            if Set(p).count > 1 { ui.linkedPadding = false }
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
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { library.importFile(url) } }
            }
            return true
        }
    }
}
