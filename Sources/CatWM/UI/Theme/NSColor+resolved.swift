import AppKit
import CoreText
import SwiftUI

extension NSColor {
    func resolved(_ appearance: NSAppearance) -> NSColor {
        var out = self
        appearance.performAsCurrentDrawingAppearance { out = self.usingColorSpace(.sRGB) ?? self }
        return out
    }
}
