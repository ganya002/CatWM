import AppKit
import CatWMKit
import SwiftUI

struct Sidebar: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    var searchFocused: FocusState<Bool>.Binding
    @ObservedObject private var library = SettingsWindow.shared.library
    @StateObject private var gaze = Gaze()

    final class Gaze: ObservableObject {
        @Published var look: CGVector?
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    private var mood: (feeling: CatFeeling, color: Color) {
        let status = settingsUI.status
        if doc.saveError != nil { return (.sad, Theme.danger) }
        if !status.trusted || !status.keybindsActive { return (.alert, Theme.warning) }
        if doc.problemCount > 0 { return (.annoyed, Theme.warning) }
        if !status.tilingEnabled { return (.sleepy, Theme.inkMuted) }
        return (.content, Theme.ink)
    }

    private static let catCentre = CGPoint(x: 40, y: SettingsWindow.titlebarHeight + 28)

    private func watch(_ phase: HoverPhase) {
        switch phase {
        case .active(let point):
            let dx = max(-1, min(1, (point.x - Self.catCentre.x) / 90))
            let dy = max(-1, min(1, (point.y - Self.catCentre.y) / 70))
            gaze.look = CGVector(dx: dx * 0.8, dy: dy * 0.5)
        case .ended:
            gaze.look = nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: SettingsWindow.titlebarHeight)
            HStack(spacing: Theme.Space.medium) {
                CatMascot(feeling: mood.feeling, look: gaze.look).frame(height: 56)
                    .foregroundStyle(mood.color)
                    .animation(Motion.fadeMedium, value: mood.color)
                Wordmark()
            }
            .padding(.leading, 6).padding(.bottom, 16)
            OSearchField(placeholder: "Search", text: $settingsUI.search, shortcut: ["⌘", "K"],
                         focus: searchFocused) {
                if let first = SettingsIndex.search(settingsUI.search, doc: doc).first { settingsUI.open(first) }
            }
            .background(Capsule().fill(Theme.surface))
            .padding(.bottom, Theme.Space.small)
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
        .padding(.horizontal, 12).padding(.bottom, Theme.Space.medium)
        .onContinuousHover(coordinateSpace: .local, perform: watch)
    }

    private func badge(_ pane: Pane) -> SideItem.Badge? {
        switch pane {
        case .general where !(settingsUI.status.trusted && settingsUI.status.keybindsActive): .attention
        case .shortcuts where doc.problemCount > 0: .count(doc.problemCount)
        default: nil
        }
    }
}

struct FeedbackButton: View {
    var body: some View {
        OIconButton(symbol: "ladybug", label: "Send feedback", tip: true) { Feedback.shared.open() }
            .frame(width: 30)
    }
}

struct Wordmark: View {
    private final class Model: ObservableObject {
        @Published var hover = false
        @Published var bumps = 0
    }
    @StateObject private var model = Model()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("CatWM").font(Theme.wordmark(26)).tracking(-0.5)
            .rotationEffect(.degrees(model.hover && !reduceMotion ? -6 : 0), anchor: .bottomLeading)
            .squish(on: model.bumps)
            .animation(Motion.snap, value: model.hover)
            .onHover { model.hover = $0 }
            .onTapGesture { model.bumps += 1 }
            .accessibilityAddTraits(.isHeader)
    }
}
