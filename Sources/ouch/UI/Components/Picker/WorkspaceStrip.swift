import AppKit
import SwiftUI

struct WorkspaceStrip: View {
    let names: [String]
    let current: String?
    let occupied: Set<String>
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names, id: \.self) { n in WorkspacePill(name: n, current: n == current, occupied: occupied.contains(n)) { pick(n) } }
        }
    }
}

private struct WorkspacePill: View {
    let name: String
    let current: Bool
    let occupied: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()

    var body: some View {
        Button(action: action) {
            Text(name).font(Theme.body(12, .medium)).oneLine()
                .foregroundStyle(current ? Theme.onAccent : hover.on ? Theme.ink : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(current ? Theme.accent : hover.on ? Theme.wellHover : .clear))
                .opacity(occupied || current || hover.on ? 1 : 0.35)
                .scaleEffect(current ? 1.04 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.on = $0 }
        .animation(Motion.spring, value: current)
        .animation(Motion.spring, value: occupied)
        .tooltip("Workspace \(name)")
        .accessibilityLabel("Workspace \(name)\(occupied ? ", has windows" : "")")
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
