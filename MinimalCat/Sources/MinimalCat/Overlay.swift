import AppKit
import MinimalCatCore
import MinimalCatSystem
import SwiftUI

/// What a held cat key shows: every window with its number, and the keys.
struct OverlayView: View {
    struct Row: Identifiable {
        let id: WindowID
        let number: Int?
        let title: String
        let app: String
        let icon: NSImage?
        let focused: Bool
    }

    let rows: [Row]
    let keyName: String
    let undo: String
    let redo: String

    private static let shown = 12
    private let columns = [GridItem(.fixed(250), spacing: 8), GridItem(.fixed(250), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if rows.isEmpty {
                Text("No windows on this Desktop")
                    .font(Theme.body)
                    .foregroundStyle(Theme.inkMuted)
                    .frame(width: 508, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(rows.prefix(Self.shown)) { row in tile(row) }
                }
                if rows.count > Self.shown {
                    Text("\(rows.count - Self.shown) more. Press Space to find one.")
                        .font(Theme.caption).foregroundStyle(Theme.inkMuted)
                }
            }
            Divider().overlay(Theme.hairline)
            keys
        }
        .padding(20)
        .floatingCard(radius: 22)
        .padding(40)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Minimal Cat")
    }

    private func tile(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Keycap(text: row.number.map(String.init) ?? "·", size: 24)
                .opacity(row.number == nil ? 0.4 : 1)
            if let icon = row.icon {
                Image(nsImage: icon).resizable().frame(width: 26, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(Theme.label).foregroundStyle(row.focused ? Theme.onAccent : Theme.ink)
                Text(row.app).font(Theme.caption)
                    .foregroundStyle(row.focused ? Theme.onAccent.opacity(0.7) : Theme.inkMuted)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(row.focused ? Theme.accent : Theme.hover.opacity(0.6)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.number.map { "Window \($0), \(row.title), \(row.app)" } ?? "\(row.title), \(row.app)")
    }

    private var keys: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 18) {
                hint(["←", "→", "↑", "↓"], "Move")
                hint(["↩"], "Big")
                hint([",", "."], "Next window")
                hint(["1–9"], "Go to window")
            }
            HStack(spacing: 18) {
                hint([undo], "Undo")
                hint([redo], "Redo")
                hint(["Space"], "Find")
                Text("Tap \(keyName) to go back")
                    .font(Theme.caption).foregroundStyle(Theme.inkMuted)
            }
        }
    }

    private func hint(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { Keycap(text: $0, size: 20) }
            Text(label).font(Theme.caption).foregroundStyle(Theme.inkMuted).padding(.leading, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
final class Overlay {
    private let panel = FloatingPanel()
    var isShown: Bool { panel.isVisible }

    func show(_ rows: [OverlayView.Row], keyName: String) {
        let undo = Command.undo.binding.map(KeyLayout.label) ?? "Z"
        let redo = Command.redo.binding.map(KeyLayout.label) ?? "Y"
        panel.show(OverlayView(rows: rows, keyName: keyName, undo: undo, redo: redo), on: activeScreen(), at: .center)
    }

    func hide() { panel.orderOut(nil) }
}
