import AppKit
import CatWMKit
import SwiftUI

extension ShortcutMap {
    @ViewBuilder
    func selection(_ key: KeyHintKeyboard.Key, code: UInt16, scale: CGFloat, size: CGSize, frame: CGRect) -> some View {
        let rect = KeyHintKeyboard.rect(of: key, scale: scale)
        let windowHeight = SettingsWindow.shared.window?.contentView?.bounds.height ?? 680
        let height = model.editorHeight, edge: CGFloat = 12
        let roomBelow = windowHeight - edge - (frame.minY + rect.maxY + 8)
        let roomAbove = frame.minY + rect.minY - 8 - edge
        let top: CGFloat = height <= roomBelow ? rect.maxY + 8
            : height <= roomAbove ? rect.minY - 8 - height
            : max(edge, windowHeight - edge - height) - frame.minY
        let width = KeyEditor.width, margin: CGFloat = 20
        let x = min(max(rect.midX, width / 2 - margin), size.width - width / 2 + margin)
        RoundedRectangle(cornerRadius: KeyHintKeyboard.cornerRadius(scale: scale) + 2, style: .continuous)
            .strokeBorder(Theme.focus, lineWidth: 2)
            .frame(width: rect.width + 4, height: rect.height + 4)
            .offset(x: rect.minX - 2, y: rect.minY - 2)
            .allowsHitTesting(false)
        KeyEditor(doc: doc, model: model, key: key, code: code,
                  flyoutLeading: x + width / 2 + Theme.submenuWidth > size.width + 120, reveal: reveal)
            .id("\(code) \(model.flags.rawValue) \(model.mode)")
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { model.editorHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newHeight in model.editorHeight = newHeight }
            })
            .frame(width: 0, height: 0, alignment: .top)
            .offset(x: x, y: top)
            .transition(.opacity)
    }

    func tooltip(_ key: KeyHintKeyboard.Key, layer: [ConfigDocument.KeyAction], scale: CGFloat,
                 width: CGFloat) -> some View {
        let rect = KeyHintKeyboard.rect(of: key, scale: scale)
        let action = layer.first { $0.code == key.code }
        var chords = [ConfigDocument.modifierCaps(model.flags) + [KeyHintKeyboard.legend(key)]]
        if let entry = modeEntry { chords.insert(entry, at: 0) }
        let tipWidth = model.tipWidth, margin: CGFloat = 28
        let shift = max(0, -margin - (rect.midX - tipWidth / 2)) + min(0, width + margin - (rect.midX + tipWidth / 2))
        return OTooltip(text: tooltipText(action: action, code: key.code), chords: chords, caret: .bottomAt(-shift))
            .fixedSize()
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { model.tipWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in model.tipWidth = newWidth }
            })
            .frame(width: 0, height: 0, alignment: .bottom)
            .offset(x: rect.midX + shift, y: rect.minY - 8)
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

    func list(_ layer: [ConfigDocument.KeyAction]) -> some View {
        let order = Dictionary(KeyHintKeyboard.keys.enumerated().compactMap { i, key in key.code.map { ($0, i) } },
                               uniquingKeysWith: { first, _ in first })
        let rank = { (code: UInt16) in (order[code] ?? 999, code) }
        let entries = Dictionary(grouping: layer, by: { $0.row.id }).values.compactMap { acts -> Entry? in
            let sorted = acts.sorted { rank($0.code) < rank($1.code) }
            guard let first = sorted.first else { return nil }
            return Entry(row: first.row, codes: sorted.map(\.code), group: KeyHint(first).group)
        }
        .sorted { rank($0.codes[0]) < rank($1.codes[0]) }
        let sections = KeyGroup.allCases.compactMap { group -> (group: KeyGroup, rows: [Entry])? in
            let rows = entries.filter { $0.group == group }
            return rows.isEmpty ? nil : (group, rows)
        }
        return Group {
            if sections.isEmpty {
                Text(model.flags.isEmpty && model.mode.isEmpty
                     ? "Global shortcuts need ⌥, ⌃ or ⌘ so they don't block typing."
                     : "No shortcuts use \(ConfigDocument.modifierCaps(model.flags).joined()) here yet.")
                    .font(Theme.body(13)).foregroundStyle(Theme.inkMuted).oneLine()
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 40, alignment: .top)],
                          alignment: .leading, spacing: Theme.Space.extraLarge) {
                    ForEach(sections, id: \.group) { section in
                        VStack(alignment: .leading, spacing: 2) {
                            OSectionHeader(section.group.title, tone: Theme.inkMuted, dot: section.group.color)
                                .padding(.bottom, Theme.Space.xxs)
                            OGroup {
                                ForEach(section.rows) { entry in row(entry) }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 940).frame(maxWidth: .infinity)
        .transaction { $0.animation = nil }
    }

    func row(_ entry: Entry) -> some View {
        Button {
            if let first = entry.codes.first, KeyHintKeyboard.key(for: first) != nil {
                model.tip = nil
                model.selected = first
            }
        } label: {
            HStack(spacing: 12) {
                Text(doc.title(entry.row)).font(Theme.body(13.5)).foregroundStyle(Theme.ink).oneLine()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Kbd(keys: doc.prettyShortcut(entry.row)).fixedSize()
            }
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { model.hotRow = entry.id } else if model.hotRow == entry.id { model.hotRow = nil }
        }
    }
}
