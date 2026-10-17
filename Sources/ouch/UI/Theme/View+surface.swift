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
