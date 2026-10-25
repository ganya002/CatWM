import AppKit
import SwiftUI

struct ActionRow: View {
    let action: QuickAction
    let hovered: Bool
    var remove: (() -> Void)?
    let pick: () -> Void

    var body: some View {
        OMenuRow(highlight: .fixed(hovered), danger: action.destructive, action: pick) {
            Text(action.title).oneLine().layoutPriority(1)
        } trailing: {
            if action.isOn {
                Image(systemName: "checkmark").font(Theme.symbol(Theme.Icon.small, .bold))
                    .foregroundStyle(Theme.accentInk)
            }
            if !action.keys.isEmpty {
                Kbd(keys: action.keys).fixedSize()
                    .opacity(hovered && remove != nil ? 0 : 1)
            }
        }
        .accessibilityLabel(action.title)
        .accessibilityValue(action.isOn ? "On" : "")
        .accessibilityHint(action.keys.isEmpty ? "" : "Shortcut \(action.keys.joined(separator: " "))")
        .accessibilityAddTraits(action.isOn ? .isSelected : [])
        .accessibilityActions {
            if let remove { Button("Delete template", action: remove) }
        }
        .overlay(alignment: .trailing) {
            if hovered, let remove {
                RemoveButton(help: "Delete \(action.title)", variant: .close, action: remove)
                    .frame(width: Theme.keycapSize, height: Theme.keycapSize)
                    .padding(.trailing, OMenuRowStyle.inset)
            }
        }
    }
}
