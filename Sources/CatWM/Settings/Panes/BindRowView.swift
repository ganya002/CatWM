import AppKit
import CatWMKit
import MacKeysCore
import SwiftUI

struct BindRowView: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
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
            let editorOpen = isRange
                && (settingsUI.expanded.contains(rowID) || summary == nil || issue?.severity == .error)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Recorder(doc: doc, settingsUI: settingsUI, row: row)
                    if isRange {
                        Text(summary?.title ?? "Custom range").font(Theme.body()).oneLine(.middle)
                            .foregroundStyle(summary == nil ? Theme.inkMuted : Theme.ink)
                        Spacer(minLength: 0)
                    } else {
                        actionMenu(i, action)
                        if row.dispatcher == "exec" {
                            OTextField(placeholder: "open -na Terminal", text: $doc.binds[i].args, mono: true)
                        } else if action == nil {
                            OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher),
                                        selection: $doc.binds[i].dispatcher)
                            OTextField(placeholder: "arguments", text: $doc.binds[i].args, mono: true)
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                    if let issue {
                        Image(systemName: issue.severity == .error
                              ? "exclamationmark.triangle.fill"
                              : "exclamationmark.circle")
                            .foregroundStyle(issue.severity == .error ? Theme.danger : Theme.warning)
                            .tooltip(issue.message)
                            .accessibilityLabel(issue.message)
                    }
                    if isRange { editToggle(open: editorOpen, locked: summary == nil || issue?.severity == .error) }
                    RemoveButton(help: "Delete shortcut") {
                        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == rowID } }
                        settingsUI.expanded.remove(rowID)
                        if settingsUI.recording == rowID { settingsUI.recording = nil }
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
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous).fill(Theme.hover)
                    .padding(.horizontal, -12)
                    .opacity(settingsUI.reveal == rowID ? 1 : 0)
            }
        }
    }

    private func rangeEditor(_ i: Int, _ row: BindRow, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                OMenuPicker(title: "Dispatcher", options: dispatcherOptions(row.dispatcher),
                            selection: $doc.binds[i].dispatcher)
                OTextField(placeholder: "1..0", text: $doc.binds[i].key, mono: true)
                    .frame(minWidth: 90, maxWidth: 150)
                Image(systemName: "arrow.right").font(Theme.symbol(Theme.Icon.small, .semibold))
                    .foregroundStyle(Theme.inkMuted)
                    .accessibilityHidden(true)
                OTextField(placeholder: "1..10", text: $doc.binds[i].args, mono: true)
                    .frame(minWidth: 90, maxWidth: 150)
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
            withAnimation(Motion.reveal) {
                if settingsUI.expanded.contains(rowID) {
                    settingsUI.expanded.remove(rowID)
                } else {
                    settingsUI.expanded.insert(rowID)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(Theme.symbol(Theme.Icon.small))
                .foregroundStyle(open ? Theme.ink : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(open ? Theme.hover : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .tooltip(open ? "Hide keys and values" : "Edit keys and values")
        .accessibilityLabel(open ? "Hide keys and values" : "Edit keys and values")
    }

    private func rangePreview(_ row: BindRow) -> String {
        guard case .success(let pairs) = BindRange.pairs(key: row.key, dispatcher: row.dispatcher, arg: row.args) else {
            return ""
        }
        let mods = ConfigText.flags(doc.resolvedMods(row.mods))
            .map { ConfigDocument.modifierCaps($0).joined() } ?? ""
        func one(_ pair: (key: String, arg: String)) -> String {
            let target = Actions.match(BindRow(mods: "", key: "", dispatcher: row.dispatcher, args: pair.arg))?.title
                ?? (pair.arg.isEmpty ? row.dispatcher : pair.arg)
            return "\(mods)\(ConfigDocument.capLabel(pair.key)) → \(target)"
        }
        let shown: [String]
        if pairs.count > 5, let last = pairs.last {
            shown = pairs.prefix(3).map(one) + ["…", one(last)]
        } else {
            shown = pairs.map(one)
        }
        return shown.joined(separator: "  ·  ")
    }

    private func actionMenu(_ i: Int, _ action: Action?) -> some View {
        let doc = doc
        return OMenuButton(items: {
            ActionMenuItems.items(current: action) { picked in
                guard doc.binds.indices.contains(i) else { return }
                doc.binds[i].dispatcher = picked.dispatcher
                if picked.dispatcher != "exec" || doc.binds[i].args.isEmpty || action?.dispatcher != "exec" {
                    doc.binds[i].args = picked.args
                }
            }
        }, label: {
            HStack(spacing: Theme.Space.extraSmall) {
                Text(action?.title ?? "Custom").font(Theme.body()).oneLine()
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.extraSmall, .semibold))
                    .foregroundStyle(Theme.inkMuted)
            }
            .foregroundStyle(Theme.ink)
            .contentShape(Rectangle())
        })
        .fixedSize()
    }
}

enum ActionMenuItems {
    static func items(current: Action? = nil, pick: @escaping (Action) -> Void) -> [MenuItem] {
        func row(_ action: Action, _ title: String) -> MenuItem {
            MenuItem(id: "a.\(action.id)", kind: current == nil ? .action : .radio, label: title,
                     checked: action.id == current?.id,
                     action: { pick(action) })
        }
        func sub(_ id: String, _ label: String, _ children: [MenuItem]) -> MenuItem {
            MenuItem(id: id, kind: .sub, label: label, width: MenuItem.fitWidth(children),
                     children: children)
        }
        return Actions.byCategory.map { cat, actions in
            sub("c.\(cat.rawValue)", cat.rawValue, Actions.menuEntries(actions).map { entry in
                switch entry {
                case .action(let action): row(action, action.title)
                case .group(let name, let list):
                    sub("g.\(name)", name, list.map { row($0, $0.short ?? $0.title) })
                }
            })
        }
    }
}
