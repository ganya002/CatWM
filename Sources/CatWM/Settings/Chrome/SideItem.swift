import AppKit
import CatWMKit
import SwiftUI

struct SideItem: View {
    enum Badge { case attention, count(Int) }
    let pane: Pane
    let selected: Bool
    let badge: Badge?
    let action: () -> Void
    @StateObject private var model = Model()

    final class Model: ObservableObject {
        @Published var hover = false
    }

    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 8) {
                Text(pane.rawValue).font(Theme.body(13.5, .medium)).oneLine()
                Spacer(minLength: 0)
                switch badge {
                case .attention:
                    Circle().fill(Theme.warning).frame(width: 8, height: 8)
                        .accessibilityLabel("Needs attention")
                case .count(let count):
                    Text("\(count)").font(Theme.body(11, .medium)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.dangerSoft))
                        .accessibilityLabel("\(count) problems")
                case nil:
                    EmptyView()
                }
            }
            .foregroundStyle(selected ? Theme.background : model.hover ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 12).frame(height: Theme.rowHeight)
            .background(Capsule().fill(selected ? Theme.ink : Theme.surface.opacity(model.hover ? 1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { model.hover = $0 }
        .animation(Motion.fade, value: model.hover)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .tipAnchor("pane.\(pane.rawValue)")
    }
}
