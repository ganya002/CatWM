import AppKit
import SwiftUI

struct CursorActionsView: View {
    @ObservedObject var model: CursorActionsModel

    static let margin: CGFloat = 28
    static let markOffset = CGSize(width: 22, height: 9)
    static let markSize: CGFloat = 56
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
                        ActionRow(action: action, hovered: model.hovered == action.id, shown: model.open, index: min(i, 8)) {
                            model.onPick?(action)
                        } hover: { inside in
                            if inside { model.hovered = action.id } else if model.hovered == action.id { model.hovered = nil }
                        }
                        .id(action.id)
                    }
                }
            }
            .onChange(of: model.hovered) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            TemplateSaveRow(name: $model.templateName, busy: model.capturing, problem: model.nameProblem,
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
        if model.capturing { return "Capturing screenshot…" }
        if model.templateDraft?.screenshot == nil { return "No screenshot. Allow screen recording to capture previews." }
        return "Return to save · Esc to cancel"
    }
}
