import AppKit
import SwiftUI
import MacKeysCore

struct BindRowView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let rowID: UUID

    private var index: Int? { doc.binds.firstIndex { $0.id == rowID } }

    private func dispatcherOptions(_ current: String) -> [(value: String, label: String)] {
        Actions.dispatchers.map { ($0, $0) } + (Actions.dispatchers.contains(current) ? [] : [(current, current)])
    }

    var body: some View {
        if let i = index {
            let row = doc.binds[i]
            let action = Actions.match(row)
            let issue = doc.issue(row)
            let isRange = BindRange.isRange(row.key)
            let summary = isRange ? Actions.rangeSummary(row) : nil
            let editorOpen = isRange && (ui.expanded.contains(rowID) || summary == nil || issue?.severity == .error)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Recorder(doc: doc, ui: ui, row: row)
                    if isRange {
                        Text(summary?.title ?? "Custom range").font(Theme.body(14)).oneLine(.middle)
                            .foregroundStyle(summary == nil ? Theme.inkMuted : Theme.ink)
                        Spacer(minLength: 0)
                    } else {
                        actionMenu(i, action)
                        if row.dispatcher == "exec" {
                            OTextField(placeholder: "open -na Terminal", text: $doc.binds[i].args, mono: true)
                        } else if action == nil {
                            OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                            OTextField(placeholder: "arguments", text: $doc.binds[i].args, mono: true)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    if let issue {
                        Image(systemName: issue.severity == .error ? "exclamationmark.triangle.fill" : "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                            .tooltip(issue.message)
                            .accessibilityLabel(issue.message)
                    }
                    if isRange { editToggle(open: editorOpen, locked: summary == nil || issue?.severity == .error) }
                    RemoveButton(help: "Delete shortcut") {
                        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == rowID } }
                        ui.expanded.remove(rowID)
                    }
                }
                if editorOpen {
                    rangeEditor(i, row, valid: issue?.severity != .error)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let issue, issue.severity == .error {
                    Text(issue.message).textStyle(.caption).foregroundStyle(Theme.danger).oneLine()
                        .padding(.leading, Recorder.width + 12)
                }
            }
            .frame(minHeight: 48)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).fill(Theme.accentSoft)
                    .padding(.horizontal, -12)
                    .opacity(ui.reveal == rowID ? 1 : 0)
            }
        }
    }

    private func rangeEditor(_ i: Int, _ row: BindRow, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher), selection: $doc.binds[i].dispatcher)
                OTextField(placeholder: "1..0", text: $doc.binds[i].key, mono: true).frame(minWidth: 90, maxWidth: 150)
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.sm, .semibold)).foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                OTextField(placeholder: "1..10", text: $doc.binds[i].args, mono: true).frame(minWidth: 90, maxWidth: 150)
                Spacer(minLength: 0)
            }
            if valid {
                Text(rangePreview(row)).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            }
        }
        .padding(.leading, Recorder.width + 12)
    }

    private func editToggle(open: Bool, locked: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                if ui.expanded.contains(rowID) { ui.expanded.remove(rowID) } else { ui.expanded.insert(rowID) }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(Theme.symbol(Theme.Icon.sm))
                .foregroundStyle(open ? Theme.accentInk : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(open ? Theme.accentSoft : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .tooltip(open ? "Hide keys and values" : "Edit keys and values")
        .accessibilityLabel(open ? "Hide keys and values" : "Edit keys and values")
    }

    private func rangePreview(_ row: BindRow) -> String {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else { return "" }
        let mods = ConfigDocument.flags(doc.resolvedMods(row.mods)).map { ConfigDocument.modifierCaps($0).joined() } ?? ""
        func one(_ p: (key: String, arg: String)) -> String {
            let target = Actions.match(BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: p.arg))?.title
                ?? (p.arg.isEmpty ? row.dispatcher : p.arg)
            return "\(mods)\(ConfigDocument.capLabel(p.key)) → \(target)"
        }
        let shown = pairs.count > 5 ? pairs.prefix(3).map(one) + ["…", one(pairs.last!)] : pairs.map(one)
        return shown.joined(separator: "  ·  ")
    }

    private func actionMenu(_ i: Int, _ action: Action?) -> some View {
        let doc = doc
        return OMenuButton(items: {
            ActionMenuItems.items(current: action) { a in
                guard doc.binds.indices.contains(i) else { return }
                doc.binds[i].dispatcher = a.dispatcher
                if a.dispatcher != "exec" || doc.binds[i].args.isEmpty || action?.dispatcher != "exec" {
                    doc.binds[i].args = a.args
                }
            }
        }) {
            HStack(spacing: 5) {
                Text(action?.title ?? "Custom").font(Theme.body(14)).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
        }
        .fixedSize()
    }
}
