import AppKit
import SwiftUI

extension MenuItem {
    static func fitWidth(_ items: [MenuItem]) -> CGFloat {
        let font = Theme.nsBody(13.5)
        let keyFont = NSFont.systemFont(ofSize: 13)
        var widest: CGFloat = 0
        for item in items where !item.hidden {
            var width = item.label.size(withAttributes: [.font: font]).width
            if let value = item.value { width += 8 + value.size(withAttributes: [.font: font]).width }
            if !item.shortcut.isEmpty {
                width += 16 + item.shortcut.joined().size(withAttributes: [.font: keyFont]).width
            }
            if item.kind == .sub { width += 18 }
            widest = max(widest, width)
        }
        return min(max(widest * 1.1 + 20 + 26 + 12 + 20, 180), 380)
    }
}
