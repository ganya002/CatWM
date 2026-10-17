import AppKit
import CoreText
import SwiftUI

extension View {
    func surface(_ density: Density, glass: Bool = false, caret: Caret = .none) -> some View {
        modifier(SurfaceModifier(density: density, glass: glass, caret: caret))
    }

    func pane() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.pane, style: .continuous)
        return clipShape(shape).background(shape.fill(Theme.surface).elevation(.popover, in: shape))
    }
}

#if DEBUG
extension GalleryExamples {
    static let panes = GalleryExample(order: 10) { AnyView(GalleryContent(m: $0).panes) }
}

extension GalleryContent {
    @ViewBuilder var panes: some View {
        block("Pane, wash and glass") {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).fill(Theme.wash)
                Text("Content pane on the wash").font(Theme.body()).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.surface)
                    .pane()
                    .padding(Theme.Space.sm)
            }
            .frame(width: 420, height: 120)
            ZStack {
                LinearGradient(colors: [Theme.accent, Theme.success], startPoint: .leading, endPoint: .trailing)
                Text("Floating glass").font(Theme.body(13.5, .medium)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, Theme.Space.xl).padding(.vertical, Theme.Space.md)
                    .floatingGlass(Capsule())
            }
            .frame(width: 420, height: 90)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            OButton("Open a popover", icon: "rectangle.on.rectangle") { m.popover.toggle() }
                .oPopover(isPresented: $m.popover) {
                    Text("Popover content").font(Theme.body()).foregroundStyle(Theme.ink).padding(Theme.Space.md)
                }
        }
    }
}
#endif
