import AppKit
import SwiftUI

struct SortNudgeView: View {
    @ObservedObject var model: SortNudgeModel
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.popover.room) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb").font(Theme.symbol(Theme.Icon.large)).foregroundStyle(Theme.accentInk)
                    .breatheEffect().frame(width: 16)
                Text("Workspace \(model.workspace) is packed").font(Theme.heading()).oneLine()
                Spacer(minLength: 4)
                OIconButton(symbol: "xmark", label: "Close tip", action: model.later).padding(.trailing, -4)
            }
            Text("\(model.count) windows on one screen. Split them into workspaces by task.")
                .font(Theme.body(13.5)).foregroundStyle(Theme.inkMuted).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            HStack(spacing: 2) {
                ForEach(0..<min(model.count, 40), id: \.self) { _ in Capsule().fill(Theme.tint).frame(height: 4) }
            }
            .padding(.top, 10).padding(.bottom, 12)
            HStack(spacing: 4) {
                OButton("Open Overview", variant: .primary, shortcut: model.keys, action: model.sort)
                OButton("Not now", variant: .ghost, action: model.later)
                Spacer(minLength: 4)
                Button("No more tips", action: model.never).buttonStyle(.plain)
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .frame(width: 276)
        .padding(.horizontal, 6).padding(.top, 4).padding(.bottom, 2)
        .surface(.medium, caret: .top(model.caret - Self.inset.leading))
        .padding(Self.inset)
        .fixedSize()
        .font(Theme.body())
    }
}
