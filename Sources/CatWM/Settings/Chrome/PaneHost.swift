import AppKit
import CatWMKit
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
                VStack(alignment: .leading, spacing: 20) {
                    header
                    switch settingsUI.pane {
                    case .general: GeneralPane(doc: doc, settingsUI: settingsUI)
                    case .layout: LayoutPane(doc: doc, settingsUI: settingsUI)
                    case .windows: WindowsPane(doc: doc, settingsUI: settingsUI)
                    case .templates: TemplatesPane(doc: doc, settingsUI: settingsUI)
                    case .motion: MotionPane(doc: doc, settingsUI: settingsUI)
                    case .shortcuts: ShortcutsPane(doc: doc, settingsUI: settingsUI)
                    }
                }
                .padding(.horizontal, Theme.Space.extraLarge).padding(.top, 22).padding(.bottom, 40)
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
                if let id { withAnimation(Motion.user) { proxy.scrollTo("bind.\(id)", anchor: .center) } }
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
        HStack(alignment: .center, spacing: Theme.Space.small) {
            Text(settingsUI.pane.rawValue).textStyle(.title).foregroundStyle(Theme.ink).oneLine()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Space.medium)
            if let kind = settingsUI.pane.configKind {
                ConfigSelector(kind: kind, library: library, width: 180)
                ConfigTransferMenu(kind: kind, library: library)
            }
        }
    }
}

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
