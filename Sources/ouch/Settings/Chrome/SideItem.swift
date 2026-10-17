import AppKit
import SwiftUI

struct SideItem: View {
    enum Badge { case attention, count(Int) }
    let pane: Pane
    let on: Bool
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
            HStack(spacing: 10) {
                Image(systemName: pane.icon)
                    .font(Theme.symbol(Theme.Icon.lg))
                    .foregroundStyle(on ? Theme.accentInk : Theme.inkMuted)
                    .frame(width: 18)
                Text(pane.rawValue).font(Theme.body(13.5, on ? .medium : .regular)).oneLine()
                Spacer(minLength: 0)
                switch badge {
                case .attention:
                    Image(systemName: "exclamationmark.triangle.fill").font(Theme.symbol(Theme.Icon.sm, .regular)).foregroundStyle(Theme.warning)
                        .accessibilityLabel("Needs attention")
                case .count(let n):
                    Text("\(n)").font(Theme.body(11, .medium)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 6).frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(Theme.dangerSoft))
                        .accessibilityLabel("\(n) problems")
                case nil:
                    EmptyView()
                }
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10).frame(height: 34)
            .background {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                if on {
                    shape.fill(Theme.surface).elevation(.sm, in: shape)
                } else {
                    shape.fill(Theme.surface.opacity(model.hover ? 0.55 : 0))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { model.hover = $0 }
        .animation(Motion.fade, value: model.hover)
        .accessibilityAddTraits(on ? .isSelected : [])
        .tipAnchor("pane.\(pane.rawValue)")
    }
}
