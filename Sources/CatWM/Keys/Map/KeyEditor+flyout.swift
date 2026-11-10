import AppKit
import CatWMKit
import SwiftUI

extension KeyEditor {
    func flyout(_ category: MenuCategory) -> some View {
        VStack(spacing: 0) {
            ForEach(Actions.menuEntries(catalog.filter { MenuCategory($0) == category })) { entry in
                switch entry {
                case .action(let action):
                    OMenuRow(action: { pick(action) }, lead: {
                        symbol(action.symbol)
                    }, label: {
                        Text(action.title).oneLine()
                    }, trailing: {
                        if isCurrent(action) { check }
                    })
                case .group(let name, let list):
                    OMenuRow(action: { pick(list.first(where: isCurrent) ?? list[0]) }, lead: {
                        symbol(list[0].symbol)
                    }, label: {
                        Text(name).oneLine()
                    }, trailing: {
                        if list.contains(where: isCurrent) { check } else {
                            Text("\(list.count)").foregroundStyle(Theme.inkFaint).monospacedDigit()
                        }
                    })
                }
            }
        }
        .frame(width: Self.flyoutWidth)
        .surface(.medium, glass: true)
    }

    func isCurrent(_ candidate: Action) -> Bool {
        guard let action else { return false }
        return action.dispatcher == candidate.dispatcher && action.args == candidate.args
    }

    func pick(_ picked: Action) {
        let wasExec = draft.dispatcher == "exec"
        draft.dispatcher = picked.dispatcher
        if picked.dispatcher != "exec" { draft.args = picked.args } else if !wasExec { draft.args = "" }
        draft.open = nil
        draft.search = ""
        if picked.dispatcher != "exec" { searching = true }
    }

    @ViewBuilder var others: some View {
        let list = doc.keyActions(in: model.mode).filter { $0.code == code && $0.flags != model.flags }
            .sorted { $0.flags.rawValue < $1.flags.rawValue }
        if !list.isEmpty {
            hairline
            VStack(alignment: .leading, spacing: 0) {
                OSectionHeader("With other modifiers", tone: Theme.inkMuted)
                    .padding(.horizontal, Theme.Space.medium).padding(.top, Theme.Space.small)
                    .padding(.bottom, Theme.Space.xxs)
                ForEach(list.prefix(4)) { other in
                    OMenuRow(action: {
                        model.held = []
                        withAnimation(Motion.fade) { model.picked = other.flags }
                    }, label: {
                        HStack(spacing: Theme.Space.small) {
                            Kbd(keys: ConfigDocument.modifierCaps(other.flags) + [KeyHintKeyboard.legend(key)])
                                .fixedSize()
                            Circle().fill(KeyHint(other).group.color).frame(width: 7, height: 7)
                            Text(other.title).oneLine()
                        }
                    }, trailing: {})
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
        guard canSave, let row = candidate else { return }
        if let i = doc.binds.firstIndex(where: { $0.id == row.id }) {
            doc.binds[i] = row
        } else {
            doc.binds.append(row)
        }
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
