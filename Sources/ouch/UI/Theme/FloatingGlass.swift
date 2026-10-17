import AppKit
import CoreText
import SwiftUI

struct FloatingGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(Theme.glass))
                .background(VisualBlur(radius: 18).clipShape(shape))
                .background(shape.fill(Theme.glass).elevation(.float, in: shape))
        }
    }
}
