import AppKit
import SwiftUI

struct OSegment<Lead: View>: View {
    let label: String
    var keys: String? = nil
    var count: Int? = nil
    let on: Bool
    var hot = false
    var thumb: Namespace.ID? = nil
    let action: () -> Void
    @ViewBuilder var lead: (Color) -> Lead

    var body: some View {
        let ink = on ? Theme.onAccent : hot ? Theme.accentInk : Theme.inkMuted
        Button(action: action) {
            HStack(spacing: 5) {
                lead(ink)
                if let keys { Text(keys).font(Theme.keys(12.5, .medium)) }
                if !label.isEmpty { Text(label).font(Theme.body(12.5, on ? .medium : .regular)).oneLine() }
                if let count {
                    Text("\(count)").font(Theme.body(12)).monospacedDigit()
                        .foregroundStyle(on ? Theme.onAccent.opacity(0.8) : Theme.inkFaint)
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, label.isEmpty ? 9 : 12).frame(height: 24)
            .background {
                if on {
                    if let thumb { Capsule().fill(Theme.accent).matchedGeometryEffect(id: "thumb", in: thumb) }
                    else { Capsule().fill(Theme.accent) }
                } else if hot {
                    Capsule().fill(Theme.accentSoft)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
