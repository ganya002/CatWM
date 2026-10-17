import AppKit
import SwiftUI

struct CursorActionsView: View {
    @ObservedObject var model: CursorActionsModel

    static var margin: CGFloat { Elevation.popover.room }
    static let markOffset = CGSize(width: 22, height: 9)
    static var markSize: CGFloat { 22 + Elevation.popover.room * 2 }
    private static let headHeight: CGFloat = 26
    private static let inset: CGFloat = 6

    static func menuSize(for actions: [QuickAction], editing: Bool = false) -> CGSize {
        if editing {
            return CGSize(width: Theme.menuWidth + Theme.Space.xxl * 4,
                          height: 2 * inset + headHeight + Theme.controlHeight + Theme.Space.xxl * 2)
        }
        let rows = CGFloat(min(actions.count, 9)) * Theme.rowHeight + (dividerIndex(actions) == nil ? 0 : divider)
        return CGSize(width: Theme.submenuWidth, height: 2 * inset + headHeight + rows)
    }

    static func contentHeight(for actions: [QuickAction]) -> CGFloat {
        CGFloat(actions.count) * Theme.rowHeight + (dividerIndex(actions) == nil ? 0 : divider)
    }

    static func rowID(at y: CGFloat, actions: [QuickAction]) -> String? {
        guard y >= 0 else { return nil }
        let row = Theme.rowHeight
        let split = dividerIndex(actions)
        var top: CGFloat = 0
        for (index, action) in actions.enumerated() {
            if index == split { top += divider }
            if y < top + row { return action.id }
            top += row
        }
        return nil
    }

    static func rowUnderPointer(x: CGFloat, y: CGFloat, width: CGFloat, actions: [QuickAction], visible: Range<CGFloat>) -> String? {
        guard x >= 0, x <= width, visible.contains(y) else { return nil }
        return rowID(at: y, actions: actions)
    }

    private static let divider: CGFloat = 9

    private static func dividerIndex(_ actions: [QuickAction]) -> Int? {
        actions.firstIndex { $0.destructive }.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        let size = Self.menuSize(for: model.actions, editing: model.templateDraft != nil)
        let grow = UnitPoint(x: min(max((model.anchor.x + Self.markOffset.width - Self.margin) / size.width, 0), 1),
                             y: min(max((model.anchor.y + Self.markOffset.height - Self.margin) / size.height, 0), 1))
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                head
                if model.templateDraft != nil {
                    editor
                } else {
                    actions.frame(height: size.height - 2 * Self.inset - Self.headHeight)
                }
            }
            .padding(Self.inset - 4)
            .frame(width: size.width, alignment: .leading)
            .surface(.md)
            .modifier(MenuEntrance(shown: model.open, from: grow))
            .allowsHitTesting(model.open)
            .offset(x: Self.margin, y: Self.margin)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workspace templates")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var head: some View {
        OSectionHeader(model.templateDraft == nil ? model.title : "Save workspace", tone: Theme.inkMuted)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: Self.headHeight, alignment: .leading)
            .accessibilityHidden(true)
    }

    private var actions: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.actions.enumerated()), id: \.element.id) { i, action in
                        if i == Self.dividerIndex(model.actions) {
                            Rectangle().fill(Theme.hairline).frame(height: 1)
                                .padding(.vertical, Theme.Space.xs).padding(.horizontal, Theme.Space.xs)
                        }
                        ActionRow(action: action, hovered: model.hovered == action.id, shown: model.open, index: min(i, 8),
                                  remove: action.remove == nil ? nil : { model.onDelete?(action) }) {
                            model.onPick?(action)
                        }
                        .id(action.id)
                    }
                }
                .background(alignment: .topLeading) {
                    RowHoverAnchor().frame(maxWidth: .infinity).frame(height: 0)
                }
                .onChange(of: model.open) { _, open in
                    model.trackPointer = open
                    if open { CursorActions.shared.armPointerTracking() }
                }
            }
            .onChange(of: model.keyboardHover) { _, id in
                if model.actions.count > 9, let id { proxy.scrollTo(id) }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            TemplateSaveRow(name: $model.templateName, busy: !model.snapshotReady, problem: model.nameProblem,
                            save: { model.onSave?() }, cancel: { model.onCancelSave?() })
            Text(editorHint).textStyle(.caption).foregroundStyle(Theme.inkMuted)
                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Space.sm)
        .frame(height: Theme.controlHeight + Theme.Space.xxl * 2, alignment: .top)
    }

    private var editorHint: String {
        if let error = model.saveError { return error }
        if !model.templateName.isEmpty, let problem = model.nameProblem { return problem }
        if !model.snapshotReady { return "Reading windows…" }
        if !model.capturing, model.templateDraft?.screenshot == nil { return "No screenshot. Allow screen recording to capture previews." }
        return "Return to save · Esc to cancel"
    }
}

private struct RowHoverAnchor: NSViewRepresentable {
    func makeNSView(context: Context) -> RowHoverView { RowHoverView() }

    func updateNSView(_ view: RowHoverView, context: Context) {
        CursorActions.shared.rowHover = view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: RowHoverView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: Theme.submenuWidth, height: 0))
    }
}

private final class RowHoverView: PassThroughView {
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
}
