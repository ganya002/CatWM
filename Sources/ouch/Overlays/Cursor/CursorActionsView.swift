import AppKit
import SwiftUI

struct CursorActionsView: View {
    @ObservedObject var model: CursorActionsModel

    static let margin: CGFloat = 28
    static let markOffset = CGSize(width: 22, height: 9)
    static let markSize: CGFloat = 56
    private static let headHeight: CGFloat = 26
    private static let inset: CGFloat = 6

    static func menuSize(for actions: [QuickAction]) -> CGSize {
        let rows = CGFloat(actions.count) * Theme.rowHeight + (dividerIndex(actions) == nil ? 0 : divider)
        return CGSize(width: Theme.submenuWidth, height: 2 * inset + headHeight + rows)
    }

    private static let divider: CGFloat = 9

    private static func dividerIndex(_ actions: [QuickAction]) -> Int? {
        actions.firstIndex { $0.destructive }.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        let size = Self.menuSize(for: model.actions)
        let grow = UnitPoint(x: min(max((model.anchor.x + Self.markOffset.width - Self.margin) / size.width, 0), 1),
                             y: min(max((model.anchor.y + Self.markOffset.height - Self.margin) / size.height, 0), 1))
        let divide = Self.dividerIndex(model.actions)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                head
                ForEach(Array(model.actions.enumerated()), id: \.element.id) { i, action in
                    if i == divide { Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4) }
                    ActionRow(action: action, hovered: model.hovered == action.id, shown: model.open, index: i) {
                        model.onPick?(action)
                    } hover: { inside in
                        if inside { model.hovered = action.id } else if model.hovered == action.id { model.hovered = nil }
                    }
                }
            }
            .padding(Self.inset - 4)
            .frame(width: Theme.submenuWidth, alignment: .leading)
            .surface(.md)
            .modifier(MenuEntrance(shown: model.open, from: grow))
            .allowsHitTesting(model.open)
            .offset(x: Self.margin, y: Self.margin)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.title.isEmpty ? "Window actions" : "Actions for \(model.title)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var head: some View {
        OSectionHeader(model.title, tone: Theme.inkMuted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.headHeight, alignment: .leading)
            .accessibilityHidden(true)
    }
}
