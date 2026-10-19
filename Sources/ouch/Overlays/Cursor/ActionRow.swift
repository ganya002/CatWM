import AppKit
import SwiftUI

struct ActionRow: View {
    let action: QuickAction
    let hovered: Bool
    let shown: Bool
    let index: Int
    var remove: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pick: () -> Void

    var body: some View {
        OMenuRow(highlight: .fixed(hovered), danger: action.destructive, action: pick) {
            Image(systemName: action.symbol)
                .symbolRenderingMode(.hierarchical)
                .font(Theme.symbol())
                .foregroundStyle(action.destructive ? Theme.danger : Theme.inkMuted)
        } label: {
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
                    .padding(.trailing, OMenuRowStyle.inset)            }
        }
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : -5)
        .animation(shown ? .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.24).delay(0.06 + 0.022 * Double(index))
                         : .easeIn(duration: 0.08), value: shown) // style-ok: staggered entrance, timed to the surface
    }
}
