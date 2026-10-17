import AppKit
import SwiftUI

struct KeyEditor: View {

    static let width: CGFloat = 340
    static let flyoutWidth: CGFloat = 268

    @ObservedObject var doc: ConfigDocument
    @ObservedObject var model: ShortcutMapModel
    let key: KeyHintKeyboard.Key
    let code: UInt16
    let flyoutLeading: Bool
    let reveal: (BindRow) -> Void
    @StateObject var draft: KeyDraft
    @FocusState var searching: Bool

    var hairline: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }

    var catalog: [Action] {
        var modes = doc.submaps.filter { !$0.isEmpty }
        if !modes.contains(where: { $0.lowercased() == "window" }) { modes.insert("window", at: 0) }
        let enter = modes.map { Action(title: "Enter \($0.capitalized) Mode", category: .app, dispatcher: "submap", args: $0, symbol: "keyboard") }
        let leave = Actions.all.filter { $0.dispatcher == "submap" && $0.args == "reset" }
        return Actions.all.filter { $0.dispatcher != "submap" } + enter + leave
    }

    var action: Action? {
        guard !draft.dispatcher.isEmpty else { return nil }
        if draft.dispatcher == "submap" {
            return catalog.first { $0.dispatcher == "submap" && $0.args.lowercased() == draft.args.lowercased() }
        }
        return Actions.match(BindRow(mods: "", key: "", dispatcher: draft.dispatcher, args: draft.args))
    }

    var title: String {
        if draft.dispatcher == "exec" { return draft.args.isEmpty ? "Run Command" : "Run “\(draft.args)”" }
        if let action { return action.title }
        if draft.dispatcher.isEmpty { return "New shortcut" }
        return "\(draft.dispatcher) \(draft.args)".trimmingCharacters(in: .whitespaces)
    }

    var candidate: BindRow? {
        guard let name = ConfigDocument.keyName(for: code), !draft.dispatcher.isEmpty, !draft.isRange else { return nil }
        var r = draft.row ?? BindRow(mods: "", key: name, dispatcher: "", args: "")
        if draft.row == nil || draft.flags != model.flags { r.mods = doc.modsString(for: draft.flags) }
        r.dispatcher = draft.dispatcher
        r.args = draft.args
        r.submap = draft.mode
        return r
    }

    var issue: (severity: ConfigDocument.Severity, message: String)? { candidate.flatMap { doc.issue($0) } }

    var changed: Bool {
        guard let row = draft.row, let c = candidate else { return true }
        return c.mods != row.mods || c.dispatcher != row.dispatcher || c.args != row.args || c.submap != row.submap
    }

    var canSave: Bool { candidate != nil && issue?.severity != .error && changed }

    var head: some View {
        let capScale = min(1, 96 / key.frame.width)
        let preview = draft.dispatcher.isEmpty ? nil : KeyHint(code: code, dispatcher: draft.dispatcher, arg: draft.args, title: title)
        var chords = [ConfigDocument.modifierCaps(draft.flags) + [KeyHintKeyboard.legend(key)]]
        if let entry = modeEntry(draft.mode) { chords.insert(entry, at: 0) }
        return HStack(spacing: 12) {
            KeyHintKeyboard.keycap(key, hint: preview, scale: capScale)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(Theme.heading(14)).oneLine()
                    .foregroundStyle(draft.dispatcher.isEmpty ? Theme.inkMuted : Theme.ink)
                HStack(spacing: 5) {
                    ForEach(Array(chords.enumerated()), id: \.offset) { i, keys in
                        if i > 0 { Text("then").font(Theme.body(11.5)).foregroundStyle(Theme.inkMuted).oneLine() }
                        Kbd(keys: keys)
                    }
                }
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 10)
        .animation(Motion.fade, value: title)
    }

    var check: some View {
        Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.sm, .semibold)).foregroundStyle(Theme.accentInk)
    }

    var hasArgument: Bool {
        draft.dispatcher == "exec" || action?.group != nil || (action == nil && !draft.dispatcher.isEmpty)
    }

    @ViewBuilder var argument: some View {
        HStack(spacing: 10) {
            if draft.dispatcher == "exec" {
                Text("Command").foregroundStyle(Theme.inkMuted).oneLine().fixedSize()
                OTextField(placeholder: "open -na Terminal", text: $draft.args, mono: true, autofocus: true)
            } else if let a = action, let group = a.group {
                let family = catalog.filter { $0.group == group }
                Text(group).oneLine()
                Spacer(minLength: 8)
                OMenuPicker(title: group, options: family.map { ($0.id, $0.short ?? $0.title) },
                            selection: Binding(get: { a.id }, set: { id in if let f = family.first(where: { $0.id == id }) { pick(f) } }))
            } else {
                Text("\(draft.dispatcher) \(draft.args)").font(Theme.mono(12)).oneLine()
                Spacer(minLength: 8)
                if let row = draft.row { OButton("Edit in Shortcuts", size: .sm) { reveal(row) } }
            }
        }
        .font(Theme.body(13))
        .padding(.horizontal, 8).frame(minHeight: 40)
        .onHover { if $0 { draft.open = nil } }
    }

    var options: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Modifiers").foregroundStyle(Theme.inkMuted).oneLine()
                Spacer(minLength: 8)
                modifierToggles
            }
            .frame(height: 38)
            if doc.submaps.count > 1 {
                hairline
                HStack(spacing: 10) {
                    Text("Shortcut set").foregroundStyle(Theme.inkMuted).oneLine()
                    Spacer(minLength: 8)
                    OMenuPicker(title: "Shortcut set", options: doc.submaps.map { ($0, $0.isEmpty ? "Global" : "\($0.capitalized) mode") },
                                selection: $draft.mode)
                }
                .frame(height: 40)
            }
        }
        .font(Theme.body(13))
        .padding(.horizontal, 8)
        .onHover { if $0 { draft.open = nil } }
    }

    var modifierToggles: some View {
        OSegmented(title: "Modifiers", options: ShortcutMapModel.modifiers.map {
            OSegmentOption(value: $0.flag.rawValue, label: "", keys: $0.glyph, help: $0.name)
        }, isOn: { draft.flags.contains(NSEvent.ModifierFlags(rawValue: $0)) },
           toggle: { draft.flags.formSymmetricDifference(NSEvent.ModifierFlags(rawValue: $0)) })
    }

    var actions: some View {
        HStack(spacing: 6) {
            if let row = draft.row, !draft.isRange {
                OButton("Remove", variant: .ghostDanger, size: .sm) { remove(row) }
            }
            Spacer(minLength: 8)
            OButton("Cancel", size: .sm) { close() }
                .keyboardShortcut(.cancelAction)
            if draft.isRange, let row = draft.row {
                OButton("Edit in Shortcuts", icon: "arrow.right", variant: .primary, size: .sm) { reveal(row) }
            } else {
                OButton("Save", variant: .primary, size: .sm, shortcut: ["↩"]) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 4)
    }

    init(doc: ConfigDocument, model: ShortcutMapModel, key: KeyHintKeyboard.Key, code: UInt16, flyoutLeading: Bool,
         reveal: @escaping (BindRow) -> Void) {
        self.doc = doc
        self.model = model
        self.key = key
        self.code = code
        self.flyoutLeading = flyoutLeading
        self.reveal = reveal
        let here = doc.keyActions(in: model.mode).first { $0.code == code && $0.flags == model.flags }
        _draft = StateObject(wrappedValue: KeyDraft(here, flags: model.flags, mode: model.mode))
    }

}
