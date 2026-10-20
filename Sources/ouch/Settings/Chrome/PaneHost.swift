import AppKit
import SwiftUI

struct PaneHost: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if !settingsUI.search.isEmpty {
                SearchResults(doc: doc, settingsUI: settingsUI)
            } else if settingsUI.showMap {
                ShortcutMap(doc: doc, settings: settingsUI)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content.id(settingsUI.pane)
            }
            StatusPill(doc: doc)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header
                    switch settingsUI.pane {
                    case .general: GeneralPane(doc: doc, settingsUI: settingsUI)
                    case .layout: LayoutPane(doc: doc, settingsUI: settingsUI)
                    case .windows: WindowsPane(doc: doc, settingsUI: settingsUI)
                    case .templates: TemplatesPane(settingsUI: settingsUI)
                    case .motion: MotionPane(doc: doc, settingsUI: settingsUI)
                    case .shortcuts: ShortcutsPane(doc: doc, settingsUI: settingsUI)
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, 22).padding(.bottom, 64)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .onChange(of: settingsUI.highlight) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(Motion.easeOut) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onChange(of: settingsUI.recording) { _, id in
                if let id { withAnimation { proxy.scrollTo("bind.\(id)", anchor: .center) } }
            }
            .onAppear {
                if let id = settingsUI.highlight { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) } }
                guard let id = settingsUI.reveal else { return }
                DispatchQueue.main.async { proxy.scrollTo("bind.\(id)", anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if settingsUI.reveal == id { withAnimation(Motion.fadeAway) { settingsUI.reveal = nil } }
                }
            }
        }
    }

    private var header: some View {
        OPageTitle(crumbs: ["Settings", settingsUI.pane.rawValue]) {
            if let kind = settingsUI.pane.configKind {
                ConfigSelector(kind: kind, library: library, width: 180)
                ConfigTransferMenu(kind: kind, library: library)
            }
        }
    }
}
