// Overlays: the cursor mark and the quick-action menu drawn in the cursor panel.
import AppKit
import SwiftUI

/// While window mode is on, a quiet mark sits down-right of the pointer. Tapping the modifier opens a
/// menu beside the pointer for the window under it: an `md` Surface of 30pt rows, each with its window-mode
/// key on the right. The controller sizes the panel to `menuSize(for:)`, so the menu fills it inside `margin`.
struct CursorActionsView: View {
    @ObservedObject var model: CursorActionsModel

    /// Room round the menu for its shadow.
    static let margin: CGFloat = 28
    /// The mark's centre from the pointer's hot spot: just right of the arrow, which runs about 12 by 18pt.
    static let markOffset = CGSize(width: 22, height: 9)
    /// The mark's panel: the disc and room for its shadow.
    static let markSize: CGFloat = 56
    private static let headHeight: CGFloat = 26
    /// Surface `md` padding (4) plus the 2pt inset between the panel and its rows.
    private static let inset: CGFloat = 6

    /// The menu itself, without the shadow margin: a submenu's width, rows of `rowHeight`, the window's name above.
    static func menuSize(for actions: [QuickAction]) -> CGSize {
        let rows = CGFloat(actions.count) * Theme.rowHeight + (dividerIndex(actions) == nil ? 0 : divider)
        return CGSize(width: Theme.submenuWidth, height: 2 * inset + headHeight + rows)
    }

    private static let divider: CGFloat = 9

    /// A hairline goes before the first destructive action, so Close is never next to a safe one.
    private static func dividerIndex(_ actions: [QuickAction]) -> Int? {
        actions.firstIndex { $0.destructive }.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        let size = Self.menuSize(for: model.actions)
        // The menu unfolds from the mark: it grows out of the mark's place, as seen from the menu's own corner.
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

    /// The window the actions are for, as a group label.
    private var head: some View {
        OSectionHeader(model.title, tone: Theme.inkMuted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.headHeight, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// The menu unfolds from the mark beside the pointer: the surface springs open from a small size at the
/// mark's place while its rows follow one after another. It leaves quicker, back toward the mark. Under
/// Reduce Motion it is a plain fade.
private struct MenuEntrance: ViewModifier {
    let shown: Bool
    let from: UnitPoint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(shown ? 1 : 0).animation(Motion.fadeMedium, value: shown)
        } else {
            // The fade is quicker than the growth, so the shape is seen opening.
            content
                .opacity(shown ? 1 : 0)
                .animation(shown ? Motion.fade : Motion.exit, value: shown)
                .scaleEffect(shown ? 1 : 0.12, anchor: from)
                .animation(shown ? Motion.pop : .timingCurve(0.4, 0, 1, 1, duration: 0.14), value: shown)
        }
    }
}

/// One action as a menu row: symbol, name, then the window-mode key as keycaps. Close keeps its danger
/// colour and gets the soft danger ground when hovered.
private struct ActionRow: View {
    let action: QuickAction
    let hovered: Bool
    let shown: Bool
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pick: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        OMenuRow(highlighted: hovered, danger: action.destructive, action: pick) {
            Image(systemName: action.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(Theme.symbol())
                .foregroundStyle(action.destructive ? Theme.danger : Theme.inkMuted)
        } label: {
            Text(action.title).oneLine().layoutPriority(1)
        } trailing: {
            if action.isOn {
                Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.sm, .bold)).foregroundStyle(Theme.accentInk)
            }
            if !action.keys.isEmpty { Kbd(keys: action.keys).fixedSize() }
        }
        .animation(Motion.fade, value: hovered)
        // Rows arrive one after another once the surface is mostly open; they leave together, quicker.
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -5)
        .animation(shown ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24).delay(0.06 + 0.022 * Double(index))
                         : .easeIn(duration: 0.08), value: shown) // style-ok: staggered entrance, timed to the surface
        .onHover(perform: hover)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.isOn ? "On" : "")
        .accessibilityHint(action.keys.isEmpty ? "" : "Shortcut \(action.keys.joined(separator: " "))")
        .accessibilityAddTraits(action.isOn ? .isSelected : [])
    }
}

/// The mark right of the pointer while window mode is on: a small raised disc with the modifier's glyph in
/// the accent, the one accent in view, hinting that a tap of that modifier opens the menu. It stays still.
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
