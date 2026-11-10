import AppKit
import CatWMKit
import SwiftUI

struct WorkspaceStrip: View {
    let names: [String]
    let current: String?
    let occupied: Set<String>
    let pick: (String) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(names, id: \.self) { name in
                WorkspacePill(name: name, current: name == current, occupied: occupied.contains(name)) { pick(name) }
            }
        }
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var workspaceExample: some View {
        WorkspaceStrip(names: (1...9).map(String.init), current: model.workspace,
                       occupied: ["1", "2", "3", "5"]) { model.workspace = $0 }
    }
}
#endif

struct WorkspacePill: View {
    let name: String
    let current: Bool
    let occupied: Bool
    let action: () -> Void
    @StateObject private var hover = Flag()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(name).font(Theme.body(12, .medium)).oneLine()
                .foregroundStyle(current ? Theme.onAccent : hover.isOn ? Theme.ink : Theme.inkMuted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(current ? Theme.accent : hover.isOn ? Theme.wellHover : .clear))
                .opacity(occupied || current || hover.isOn ? 1 : 0.35)
                .scaleEffect(current ? 1.04 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale(scale: 0.88))
        .onHover { hover.isOn = $0 }
        .animation(reduceMotion ? Motion.fade : Motion.spring, value: current)
        .animation(reduceMotion ? Motion.fade : Motion.spring, value: occupied)
        .accessibilityLabel("Workspace \(name)\(occupied ? ", has windows" : "")")
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}
