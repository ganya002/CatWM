import AppKit
import CatWMKit
import MacKeysCore
import SwiftUI

struct Recorder: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    let row: BindRow
    static let width: CGFloat = 150

    var body: some View {
        let recording = settingsUI.recording == row.id
        Button {
            settingsUI.recording = recording ? nil : row.id
        } label: {
            Group {
                if recording {
                    HStack(spacing: 6) {
                        Image(systemName: "record.circle").font(Theme.symbol(Theme.Icon.small, .semibold))
                        Text(BindRange.isRange(row.key) ? "Press modifiers…" : "Press keys…")
                    }
                    .font(TextStyle.caption.font).foregroundStyle(Theme.accentInk).oneLine()
                } else if row.key.isEmpty {
                    Text("Click to record").font(TextStyle.caption.font).foregroundStyle(Theme.inkFaint).oneLine()
                } else {
                    Kbd(keys: doc.prettyShortcut(row)).squish(on: row.mods + row.key, anchor: .center)
                }
            }
            .padding(.horizontal, 6)
            .frame(width: Self.width, height: 30, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(recording ? Theme.accentSoft : .clear))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(recording ? Theme.accent : Theme.hairline,
                              style: StrokeStyle(lineWidth: recording ? 1.5 : 1,
                                                 dash: row.key.isEmpty && !recording ? [3] : [])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(recording
                            ? "Recording shortcut"
                            : "Shortcut \(doc.prettyShortcut(row).joined()). Click to record")
    }
}
