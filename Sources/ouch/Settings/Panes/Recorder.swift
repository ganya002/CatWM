import AppKit
import SwiftUI
import MacKeysCore

struct Recorder: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    let row: BindRow
    static let width: CGFloat = 150

    var body: some View {
        let recording = ui.recording == row.id
        Button {
            ui.recording = recording ? nil : row.id
        } label: {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle").font(Theme.symbol(Theme.Icon.sm, .semibold))
                        Text(BindRange.isRange(row.key) ? "Press modifiers…" : "Press keys…")
                    }
                    .font(Theme.body(12.5, .medium)).foregroundStyle(Theme.accentInk).oneLine()
                } else if row.key.isEmpty {
                    Text("Click to record").font(Theme.body(12.5)).foregroundStyle(Theme.inkFaint).oneLine()
                } else {
                    Kbd(keys: doc.prettyShortcut(row)).squish(on: row.mods + row.key, anchor: .center)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.width, height: 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(recording ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .strokeBorder(recording ? Theme.accent : Theme.hairline,
                              style: StrokeStyle(lineWidth: recording ? 1.5 : 1, dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tooltip(recording ? (row.submap.isEmpty || BindRange.isRange(row.key) ? "Esc cancels" : "Click to cancel")
              : "Click to record a new shortcut")
        .accessibilityLabel(recording ? "Recording shortcut" : "Shortcut \(doc.prettyShortcut(row).joined()). Click to record")
    }
}
