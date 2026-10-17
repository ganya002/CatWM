import AppKit
import SwiftUI

extension KeyEditor {
    func flyout(_ c: MenuCategory) -> some View {
        VStack(spacing: 0) {
            ForEach(Actions.menuEntries(catalog.filter { MenuCategory($0) == c })) { entry in
                switch entry {
                case .action(let a):
                    OMenuRow(action: { pick(a) }) {
                        symbol(a.symbol)
                    } label: {
                        Text(a.title).oneLine()
                    } trailing: {
                        if isCurrent(a) { check }
                    }
                case .group(let name, let list):
                    OMenuRow(action: { pick(list.first(where: isCurrent) ?? list[0]) }) {
                        symbol(list[0].symbol)
                    } label: {
                        Text(name).oneLine()
                    } trailing: {
                        if list.contains(where: isCurrent) { check } else {
                            Text("\(list.count)").foregroundStyle(Theme.inkFaint).monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(width: Self.flyoutWidth)
        .surface(.md, glass: true)
    }

    func isCurrent(_ a: Action) -> Bool {
        guard let action else { return false }
        return action.dispatcher == a.dispatcher && action.args == a.args
    }

    func pick(_ a: Action) {
        let wasExec = draft.dispatcher == "exec"
        draft.dispatcher = a.dispatcher
        if a.dispatcher != "exec" { draft.args = a.args } else if !wasExec { draft.args = "" }
        draft.open = nil
        draft.search = ""
        if a.dispatcher != "exec" { searching = true }
    }

    @ViewBuilder var others: some View {
        let list = doc.keyActions(in: model.mode).filter { $0.code == code && $0.flags != model.flags }
            .sorted { $0.flags.rawValue < $1.flags.rawValue }
        if !list.isEmpty {
            hairline
            VStack(alignment: .leading, spacing: 0) {
                OSectionHeader("With other modifiers", tone: Theme.inkMuted)
                    .padding(.horizontal, 10).padding(.top, Theme.Space.sm).padding(.bottom, Theme.Space.xxs)
                ForEach(list.prefix(4)) { a in
                    OMenuRow(action: {
                        model.held = []
                        withAnimation(Motion.fade) { model.picked = a.flags }
                    }) {
                        HStack(spacing: Theme.Space.sm) {
                            Kbd(keys: ConfigDocument.modifierCaps(a.flags) + [KeyHintKeyboard.legend(key)]).fixedSize()
                            Circle().fill(KeyHint(a).group.color).frame(width: 7, height: 7)
                            Text(a.title).oneLine()
                        }
                    } trailing: {}
                    .tooltip("Show \(ConfigDocument.modifierCaps(a.flags).joined()) shortcuts")
                }
            }
            .padding(.bottom, 4)
        }
    }

    func close() {
        withAnimation(Motion.fade) { model.selected = nil }
    }

    func remove(_ row: BindRow) {
        withAnimation(Motion.easeOut) { doc.binds.removeAll { $0.id == row.id } }
        close()
    }

    func save() {
        guard canSave, let r = candidate else { return }
        if let i = doc.binds.firstIndex(where: { $0.id == r.id }) { doc.binds[i] = r } else { doc.binds.append(r) }
        let flags = draft.flags, mode = draft.mode
        close()
        if mode != model.mode {
            model.mode = mode
            DispatchQueue.main.async { model.held = []; model.picked = flags }
        } else if flags != model.flags {
            model.held = []
            withAnimation(Motion.fade) { model.picked = flags }
        }
    }
}
