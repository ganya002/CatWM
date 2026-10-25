import AppKit
import SwiftUI

struct MenuBarTipView: View {
    @ObservedObject var model: MenuBarTipModel
    static var inset: EdgeInsets { EdgeInsets(all: Elevation.popover.room) }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: model.state == .good ? "checkmark.circle.fill" : "lightbulb")
                .font(Theme.symbol(Theme.Icon.large))
                .foregroundStyle(model.state == .good ? Theme.success : Theme.accentInk)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.heading()).oneLine()
                if let detail {
                    Text(detail).font(Theme.body(12.5)).lineSpacing(1.5).foregroundStyle(Theme.inkMuted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(width: model.state == .good ? nil : 288, alignment: .leading)
        .surface(.medium, caret: model.caret.map { .top($0 - Self.inset.leading) } ?? .none)
        .padding(Self.inset)
        .fixedSize()
    }

    private var title: String {
        switch model.state {
        case .move: "Keep CatWM in reach"
        case .good: "Good spot for CatWM"
        case .hidden: "CatWM is behind the notch"
        }
    }

    private var detail: String? {
        switch model.state {
        case .good: nil
        case .move: "Items on the left hide first. Move CatWM right in Control Center › Edit Controls."
        case .hidden: "Move it right, near the clock, in Control Center › Edit Controls."
        }
    }
}
