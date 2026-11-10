import AppKit
import CatWMKit
import CoreText
import SwiftUI

extension View {
    func surface(_ density: Density, glass: Bool = false, caret: Caret = .none) -> some View {
        modifier(SurfaceModifier(density: density, glass: glass, caret: caret))
    }

    func pane(shadow: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.pane, style: .continuous)
        return clipShape(shape).background {
            if shadow { shape.fill(Theme.surface).elevation(.popover, in: shape) } else { shape.fill(Theme.surface) }
        }
    }
}

#if DEBUG
extension GalleryExamples {
    static let panes = GalleryExample(order: 10) { AnyView(GalleryContent(model: $0).panes) }
}

extension GalleryContent {
    @ViewBuilder var panes: some View {
        block("Pane, wash and glass") {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).fill(Theme.wash)
                Text("Content pane on the wash").font(Theme.body()).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
                    .pane()
                    .padding(Elevation.popover.room)
            }
            .frame(width: 420, height: 180)
            ZStack {
                LinearGradient(colors: [Theme.accent, Theme.success], startPoint: .leading, endPoint: .trailing)
                Text("Floating glass").font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.extraLarge).padding(.vertical, Theme.Space.medium)
                    .floatingGlass(Capsule())
            }
            .frame(width: 420, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            OButton("Open a popover", icon: "rectangle.on.rectangle") { model.popover.toggle() }
                .oPopover(isPresented: $model.popover) {
                    Text("Popover content").font(Theme.body()).foregroundStyle(Theme.ink).padding(Theme.Space.medium)
                }
        }
    }
}
#endif
