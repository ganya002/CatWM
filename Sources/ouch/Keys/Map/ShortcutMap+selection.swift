import AppKit
import SwiftUI

extension ShortcutMap {
    @ViewBuilder
    func selection(_ k: KeyHintKeyboard.Key, code: UInt16, scale: CGFloat, size: CGSize, frame: CGRect) -> some View {
        let r = KeyHintKeyboard.rect(of: k, scale: scale)
        let windowHeight = SettingsWindow.shared.window?.contentView?.bounds.height ?? 680
        let h = model.editorHeight, edge: CGFloat = 12
        let roomBelow = windowHeight - edge - (frame.minY + r.maxY + 8)
        let roomAbove = frame.minY + r.minY - 8 - edge
        let top: CGFloat = h <= roomBelow ? r.maxY + 8
            : h <= roomAbove ? r.minY - 8 - h
            : max(edge, windowHeight - edge - h) - frame.minY
        let w = KeyEditor.width, margin: CGFloat = 20
        let x = min(max(r.midX, w / 2 - margin), size.width - w / 2 + margin)
        RoundedRectangle(cornerRadius: KeyHintKeyboard.cornerRadius(scale: scale) + 2, style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .frame(width: r.width + 4, height: r.height + 4)
            .offset(x: r.minX - 2, y: r.minY - 2)
            .allowsHitTesting(false)
        KeyEditor(doc: doc, model: model, key: k, code: code, flyoutLeading: x + w / 2 + Theme.submenuWidth > size.width + 120,
                  reveal: reveal)
            .id("\(code) \(model.flags.rawValue) \(model.mode)")
            .fixedSize()
            .background(GeometryReader { p in
                Color.clear
                    .onAppear { model.editorHeight = p.size.height }
                    .onChange(of: p.size.height) { _, h in model.editorHeight = h }
            })
            .frame(width: 0, height: 0, alignment: .top)
            .offset(x: x, y: top)
            .transition(.opacity)
    }

    func tooltip(_ k: KeyHintKeyboard.Key, layer: [ConfigDocument.KeyAction], scale: CGFloat, width: CGFloat) -> some View {
        let r = KeyHintKeyboard.rect(of: k, scale: scale)
        let action = layer.first { $0.code == k.code }
        var chords = [ConfigDocument.modifierCaps(model.flags) + [KeyHintKeyboard.legend(k)]]
        if let entry = modeEntry { chords.insert(entry, at: 0) }
        let w = model.tipWidth, margin: CGFloat = 28
        let shift = max(0, -margin - (r.midX - w / 2)) + min(0, width + margin - (r.midX + w / 2))
        return OTooltip(text: tooltipText(action: action, code: k.code), chords: chords, caret: .bottomAt(-shift))
            .fixedSize()
            .background(GeometryReader { p in
                Color.clear
                    .onAppear { model.tipWidth = p.size.width }
                    .onChange(of: p.size.width) { _, w in model.tipWidth = w }
            })
            .frame(width: 0, height: 0, alignment: .bottom)
            .offset(x: r.midX + shift, y: r.minY - 8)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    func tooltipText(action: ConfigDocument.KeyAction?, code: UInt16?) -> String {
        if let title = action?.title { return title }
        guard let code else { return "No shortcut. Click to add one." }
        if ConfigDocument.keyName(for: code) == nil { return "Can't take a shortcut yet" }
        if model.mode.isEmpty, model.flags.isEmpty { return "Pick a modifier to add a shortcut" }
        return "No shortcut. Click to add one."
    }

    func legend(_ all: [ConfigDocument.KeyAction]) -> some View {
        let present = Set(all.map { KeyHint($0).group })
        return HStack(spacing: 16) {
            ForEach(KeyGroup.allCases.filter(present.contains)) { g in
                HStack(spacing: 6) {
                    Circle().fill(g.color).frame(width: 7, height: 7)
                    Text(g.title).foregroundStyle(Theme.inkMuted).oneLine()
                }
                .fixedSize()
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                Text("Hold ⌃ ⌥ ⇧ ⌘ to switch layers, click a key to edit").fixedSize()
                Text("Click a key to edit").fixedSize()
                Color.clear.frame(width: 0)
            }
            .foregroundStyle(Theme.inkFaint)
        }
        .font(Theme.body(12.5))
        .frame(height: 20)
    }

    func list(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let order = Dictionary(KeyHintKeyboard.keys.enumerated().compactMap { i, k in k.code.map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
        let rank = { (c: UInt16) in (order[c] ?? 999, c) }
        let entries = Dictionary(grouping: layer, by: { $0.row.id }).values.compactMap { acts -> Entry? in
            let sorted = acts.sorted { rank($0.code) < rank($1.code) }
            guard let first = sorted.first else { return nil }
            return Entry(row: first.row, codes: sorted.map(\.code), group: KeyHint(first).group)
        }
        .sorted { rank($0.codes[0]) < rank($1.codes[0]) }
        let sections = KeyGroup.allCases.compactMap { g -> (group: KeyGroup, rows: [Entry])? in
            let rows = entries.filter { $0.group == g }
            return rows.isEmpty ? nil : (g, rows)
        }
        return Group {
            if sections.isEmpty {
                Text(model.flags.isEmpty && model.mode.isEmpty ? "Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing."
                     : "No shortcuts use \(ConfigDocument.modifierCaps(model.flags).joined()) here yet.")
                    .font(Theme.body(13)).foregroundStyle(Theme.inkMuted).oneLine()
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 40, alignment: .top)], alignment: .leading, spacing: 28) {
                    ForEach(sections, id: \.group) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            OSectionHeader(section.group.title, tone: Theme.inkMuted, dot: section.group.color)
                                .padding(.bottom, Theme.Space.xxs)
                            OGroup {
                                ForEach(section.rows) { e in row(e) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 940).frame(maxWidth: .infinity)
        .transaction { $0.animation = nil }
    }

    func row(_ e: Entry) -> some View {
        Button {
            if let first = e.codes.first, KeyHintKeyboard.key(for: first) != nil {
                model.tip = nil
                model.selected = first
            }
        } label: {
            HStack(spacing: 12) {
                Text(doc.title(e.row)).font(Theme.body(13.5)).foregroundStyle(Theme.ink).oneLine()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Kbd(keys: doc.prettyShortcut(e.row)).fixedSize()
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { on in
            if on { model.hotRow = e.id } else if model.hotRow == e.id { model.hotRow = nil }
        }
    }
}
