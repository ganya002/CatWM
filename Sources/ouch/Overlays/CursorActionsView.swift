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
        Text(model.title)
            .font(Theme.body(12, .medium)).tracking(0.24).oneLine()
            .foregroundStyle(Theme.inkMuted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.headHeight, alignment: .leading)
            .accessibilityHidden(true)
    }
}

private struct MenuEntrance: ViewModifier {
    let shown: Bool
    let from: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(.easeOut(duration: Theme.medium), value: shown)
        } else {
            content
                .opacity(shown ? 1 : 0)
                .animation(shown ? .easeOut(duration: 0.1) : .easeIn(duration: 0.12), value: shown)
                .scaleEffect(shown ? 1 : 0.12, anchor: from)
                .animation(shown ? .spring(response: 0.36, dampingFraction: 0.8) : .timingCurve(0.4, 0, 1, 1, duration: 0.14),
                           value: shown)
        }
    }
}

private struct ActionRow: View {
    let action: QuickAction
    let hovered: Bool
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pick: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 10) {
                Image(systemName: action.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(action.destructive ? Theme.danger : Theme.inkMuted)
                    .frame(width: 16)
                Text(action.title)
                    .font(Theme.body(13.5)).oneLine()
                    .foregroundStyle(action.destructive ? Theme.danger : Theme.ink)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if action.isOn {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accentInk)
                }
                if !action.key.isEmpty { Kbd(keys: [action.key]).fixedSize() }
            }
            .padding(.horizontal, 10)
            .frame(height: Theme.rowHeight)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                .fill(hovered ? (action.destructive ? Theme.dangerSoft : Theme.well) : .clear))
            .animation(.easeOut(duration: Theme.fast), value: hovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -5)
        .animation(shown ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24).delay(0.06 + 0.022 * Double(index))
                         : .easeIn(duration: 0.08), value: shown)
        .onHover(perform: hover)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.isOn ? "On" : "")
        .accessibilityHint(action.key.isEmpty ? "" : "Key \(action.key)")
        .accessibilityAddTraits(action.isOn ? .isSelected : [])
    }
}

struct CursorMarkView: View {
    @ObservedObject var model: CursorActionsModel

    var body: some View {
        let disc = Circle()
        disc.fill(Theme.surfaceRaised)
            .frame(width: 22, height: 22)
            .elevation(.popover, in: disc)
            .overlay(Text(model.modGlyph).font(Theme.keys(12, .bold)).foregroundStyle(Theme.accent))
            .frame(width: CursorActionsView.markSize, height: CursorActionsView.markSize)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
