import AppKit
import CoreText
import SwiftUI

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
