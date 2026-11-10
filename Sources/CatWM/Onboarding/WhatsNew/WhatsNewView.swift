import AppKit
import CatWMKit
import SwiftUI

struct WhatsNewView: View {
    @ObservedObject var model: WhatsNewModel
    static let width: CGFloat = 344
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.float.room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                OIconButton(symbol: "xmark", label: "Close", action: model.close).padding(.leading, -6)
                Image(systemName: "sparkles").font(Theme.symbol()).foregroundStyle(Theme.accentInk)
                Text("New in \(model.versions)").kicker().oneLine()
                Spacer(minLength: 0)
            }
            .frame(minHeight: 22)
            Text("What's new in CatWM").textStyle(.title).oneLine().padding(.top, 12).padding(.bottom, 6)
            ForEach(Array(model.features.enumerated()), id: \.element.id) { i, feature in
                row(feature).padding(.vertical, Theme.Space.small)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) } }
            }
            HStack {
                Spacer()
                OButton(model.canTour ? "Show me" : "Got it", variant: .primary, shortcut: ["↩"],
                        action: model.canTour ? model.tour : model.close)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Theme.Space.small)
        }
        .frame(width: Self.width - 40)
        .surface(.large, caret: model.caret.map { .top($0) } ?? .none)
        .padding(Self.inset)
        .fixedSize()
    }

    private func row(_ feature: Release.Feature) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.medium) {
            Image(systemName: feature.symbol).font(Theme.symbol()).foregroundStyle(Theme.inkMuted).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(Theme.heading()).oneLine()
                Text(feature.text).font(Theme.body()).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let action = feature.action {
                    OButton(action.label, variant: .ghost, size: .small) { model.run(action.run) }
                        .padding(.leading, -11).padding(.top, 2)
                }
            }
        }
    }
}

final class WhatsNewModel: ObservableObject {
    @Published var versions = ""
    @Published var features: [Release.Feature] = []
    @Published var caret: CGFloat?
    var canTour: Bool { features.contains { $0.tour != nil } }
    var close: () -> Void = {}
    var tour: () -> Void = {}
    var run: (() -> Void) -> Void = { _ in }
}
