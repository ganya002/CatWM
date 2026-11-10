import AppKit
import CatWMKit
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

extension View {
    func floatingGlass<S: InsettableShape>(_ shape: S) -> some View { modifier(FloatingGlass(shape: shape)) }
}

struct VisualBlur: NSViewRepresentable {
    var radius: CGFloat
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = .behindWindow
        view.maskImage = Self.mask(radius)
        return view
    }
    func updateNSView(_: NSVisualEffectView, context _: Context) {}

    private static func mask(_ radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
