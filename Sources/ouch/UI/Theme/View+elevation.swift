import AppKit
import CoreText
import SwiftUI

extension View {
    func elevation<S: Shape>(_ e: Elevation, in shape: S) -> some View {
        let ring = Theme.hairline
        let drop = Color(nsColor: NSColor(name: nil) { a in
            let dark = Theme.isDark(a)
            switch e {
            case .sm: return NSColor.black.withAlphaComponent(dark ? 0.4 : 0.06)
            case .knob: return NSColor.black.withAlphaComponent(0.32)
            case .popover: return NSColor.black.withAlphaComponent(dark ? 0.65 : 0.22)
            case .float: return NSColor.black.withAlphaComponent(dark ? 0.75 : 0.35)
            }
        })
        return self
            .overlay(shape.stroke(ring, lineWidth: e == .popover || e == .float ? 1 : 0))
            .shadow(color: drop, radius: e.radius, y: e.y)
    }

    func legible(strong: Bool = false) -> some View {
        shadow(color: .black.opacity(strong ? 0.45 : 0.3), radius: strong ? 8 : 12, y: strong ? 2 : 4)
    }
}
