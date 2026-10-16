// Settings: root view, sidebar, pane host, search results, status pill and Advanced section.
import AppKit
import SwiftUI

// MARK: - Root

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
                .padding(.vertical, 8).padding(.trailing, 8)
        }
        .sheet(isPresented: $feedback.isOpen) { FeedbackSheet(feedback: feedback) }
        .background(Theme.wash.ignoresSafeArea())
        .overlayPreferenceValue(TipAnchorKey.self) { SettingsTipLayer(anchors: $0) }
        .onChange(of: ui.pane) { _, p in Tips.shared.paneShown(p) }
        // Applying a config, undo or reset can leave unequal paddings; the single slider would flatten them.
        .onChange(of: [doc.config.paddingTop, doc.config.paddingBottom, doc.config.paddingLeft, doc.config.paddingRight]) { _, p in
            if Set(p).count > 1 { ui.linkedPadding = false }
        }
        .ignoresSafeArea()
        .font(Theme.body())
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .background {
            // ⌘K focuses the settings search.
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

// MARK: - Sidebar

private struct Sidebar: View {
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

/// A sidebar item straight on the wash; the selected one is a `surface` pill.
private struct SideItem: View {
    enum Badge { case attention, count(Int) }
    let pane: Pane
    let on: Bool
    let badge: Badge?
    let action: () -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var hover = false
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(Theme.symbol(Theme.Icon.lg))
                    .foregroundStyle(on ? Theme.accentInk : Theme.inkMuted)
                    .frame(width: 18)
                Text(pane.rawValue).font(Theme.body(13.5, on ? .medium : .regular)).oneLine()
                Spacer(minLength: 0)
                switch badge {
                case .attention:
                    Image(systemName: "exclamationmark.triangle.fill").font(Theme.symbol(Theme.Icon.sm, .regular)).foregroundStyle(Theme.warning)
                        .accessibilityLabel("Needs attention")
                case .count(let n):
                    Text("\(n)").font(Theme.body(11, .medium)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.dangerSoft))
                        .accessibilityLabel("\(n) problems")
                case nil:
                    EmptyView()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).frame(height: 34)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                if on {
                    shape.fill(Theme.surface).elevation(.sm, in: shape)
                } else {
                    shape.fill(Theme.surface.opacity(model.hover ? 0.55 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { model.hover = $0 }
        .animation(Motion.fade, value: model.hover)
        .accessibilityAddTraits(on ? .isSelected : [])
        .tipAnchor("pane.\(pane.rawValue)")
    }
}

/// The logo. It tips like the window on the icon when hovered, and takes a bump when clicked.
private struct Wordmark: View {
    private final class Model: ObservableObject {
        @Published var hover = false
        @Published var bumps = 0
    }
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("Ouch").font(Theme.wordmark(19))
            .rotationEffect(.degrees(model.hover && !reduceMotion ? -6 : 0), anchor: .bottomLeading)
            .squish(on: model.bumps)
            .animation(Motion.snap, value: model.hover)
            .onHover { model.hover = $0 }
            .onTapGesture { model.bumps += 1 }
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Pane host

private struct PaneHost: View {
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
                // After the Advanced section has had a moment to open.
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

    /// Breadcrumb, the 40pt light title, and the pane's config selector.
    private var header: some View {
        OPageTitle(crumbs: ["Settings", ui.pane.rawValue], title: ui.pane.rawValue) {
            if let kind = ui.pane.configKind {
                ConfigSelector(kind: kind, library: library, width: 180)
                ConfigTransferMenu(kind: kind, library: library)
            }
        }
    }
}

// MARK: - Search results

private struct SearchResults: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI

    var body: some View {
        let results = SettingsIndex.search(ui.search, doc: doc)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // The same page title as the panes, so the title doesn't jump when results replace a pane.
                OPageTitle(crumbs: ["Settings", "Search"], title: "“\(ui.search)”")
                if results.isEmpty {
                    Text("Nothing matches. Try another word, like “gaps” or “focus”.")
                        .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).oneLine()
                }
                ForEach(Pane.allCases) { p in
                    let here = results.filter { $0.pane == p }
                    if !here.isEmpty {
                        OGroup(p.rawValue) {
                            ForEach(here) { r in ResultRow(entry: r, first: r.id == results.first?.id) { ui.open(r) } }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.page).padding(.top, 22).padding(.bottom, 40)
            .frame(maxWidth: 660, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ResultRow: View {
    let entry: SettingEntry
    let first: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: entry.bind != nil ? "command" : entry.pane.icon)
                    .font(Theme.symbol()).foregroundStyle(Theme.accentInk).frame(width: 18)
                Text(entry.title).font(Theme.body(14)).oneLine()
                if entry.advanced {
                    Text("Advanced").textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
                Spacer(minLength: 8)
                if first { Text("↩").font(Theme.keys(12)).foregroundStyle(Theme.inkMuted) }
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.sm, .semibold)).foregroundStyle(Theme.inkMuted)
                    .opacity(hover.on ? 1 : 0)
            }
            .padding(.horizontal, 10).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(hover.on ? Theme.well : .clear))
            .padding(.horizontal, -10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
    }
}

// MARK: - Status

/// A small glass capsule over the bottom of the pane: a brief "Saved" when a change lands, problems
/// while there are any, and "Undo All Changes" once something changed since the window opened.
private struct StatusPill: View {
    @ObservedObject var doc: ConfigDocument
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var saved = false
        private var hide: DispatchWorkItem?

        func flash() {
            withAnimation(Motion.easeOut) { saved = true }
            hide?.cancel()
            let work = DispatchWorkItem { [weak self] in withAnimation(Motion.fadeSlow) { self?.saved = false } }
            hide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
        }
    }

    private enum Message: Equatable { case error(String), problems(Int), skipped(Int), saved }

    /// What to say, most urgent first. Saving itself takes a few milliseconds, so it isn't announced.
    private var message: Message? {
        if let err = doc.saveError { return .error(err) }
        if doc.problemCount > 0 { return .problems(doc.problemCount) }
        if model.saved { return .saved }
        if !doc.fileErrors.isEmpty { return .skipped(doc.fileErrors.count) }
        return nil
    }

    var body: some View {
        let message = message, undo = doc.hasChangesSinceOpen
        Group {
            if message != nil || undo {
                HStack(spacing: 10) {
                    if let message { label(message).transition(.opacity) }
                    if message != nil && undo { Rectangle().fill(Theme.hairline).frame(width: 1, height: 16) }
                    if undo {
                        OButton("Undo All Changes", icon: "arrow.uturn.backward", size: .sm) { doc.undoAllChanges() }
                        .tooltip("Go back to how things were when you opened Settings")
                    }
                }
                .padding(.leading, message == nil ? 5 : 14).padding(.trailing, undo ? 5 : 14)
                .frame(height: 36)
                .floatingGlass(Capsule())
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.easeOut, value: message)
        .animation(Motion.easeOut, value: undo)
        .onChange(of: doc.isDirty) { was, now in
            if was && !now && doc.saveError == nil { model.flash() }
        }
    }

    @ViewBuilder private func label(_ m: Message) -> some View {
        switch m {
        case .error(let err):
            OStatus(kind: .danger, text: "Couldn't save: \(err)").tooltip(err)
        case .problems(let n):
            OStatus(kind: .warning, text: "Fix \(n) shortcut\(n == 1 ? "" : "s") to save")
        case .skipped(let n):
            OStatus(kind: .warning, text: "\(n) line\(n == 1 ? "" : "s") in the config file skipped")
                .tooltip(doc.fileErrors.joined(separator: "\n"))
        case .saved:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(Theme.symbol(Theme.Icon.sm, .semibold))
                    .foregroundStyle(Theme.success)
                Text("Saved").font(Theme.body(12.5, .medium)).foregroundStyle(Theme.inkMuted)
            }
        }
    }
}

// MARK: - Advanced

/// The collapsed section at the bottom of a pane, holding what it doesn't need to show up front.
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


/// Send Feedback at the foot of the sidebar.
private struct FeedbackButton: View {
    var body: some View {
        OIconButton(symbol: "ladybug", label: "Send feedback") { Feedback.shared.open() }
            .frame(width: 30) // the share button above is 30 wide: centred under it
    }
}
