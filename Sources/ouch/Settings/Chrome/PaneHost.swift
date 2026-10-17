import AppKit
import SwiftUI

struct PaneHost: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = SettingsWindow.shared.library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            if !ui.search.isEmpty {
                SearchResults(doc: doc, ui: ui)
            } else if ui.showMap {
                ShortcutMap(doc: doc, ui: ui)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            } else {
                content.id(ui.pane)
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
                    switch ui.pane {
                    case .general: GeneralPane(doc: doc, ui: ui)
                    case .layout: LayoutPane(doc: doc, ui: ui)
                    case .windows: WindowsPane(doc: doc, ui: ui)
                    case .motion: MotionPane(doc: doc, ui: ui)
                    case .shortcuts: ShortcutsPane(doc: doc, ui: ui)
                    }
                }
                .padding(.horizontal, Theme.Space.page).padding(.top, 22).padding(.bottom, 64)
                .frame(maxWidth: 660, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .onChange(of: ui.highlight) { _, id in
                guard let id else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    withAnimation(Motion.easeOut) { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onChange(of: ui.recording) { _, id in
                if let id { withAnimation { proxy.scrollTo("bind.\(id)", anchor: .center) } }
            }
            .onAppear {
                if let id = ui.highlight { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) } }
                guard let id = ui.reveal else { return }
                DispatchQueue.main.async { proxy.scrollTo("bind.\(id)", anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    if ui.reveal == id { withAnimation(Motion.fadeAway) { ui.reveal = nil } }
                }
            }
        }
    }

    private var header: some View {
        OPageTitle(crumbs: ["Settings", ui.pane.rawValue], title: ui.pane.rawValue) {
            if let kind = ui.pane.configKind {
                ConfigSelector(kind: kind, library: library, width: 180)
                ConfigTransferMenu(kind: kind, library: library)
            }
        }
    }
}
