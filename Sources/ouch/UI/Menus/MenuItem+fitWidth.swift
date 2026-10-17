import AppKit
import SwiftUI

extension MenuItem {
    static func fitWidth(_ items: [MenuItem]) -> CGFloat {
        let font = Theme.nsBody(13.5)
        let keyFont = NSFont.systemFont(ofSize: 13)
        var widest: CGFloat = 0
        for i in items where !i.hidden {
            var w = (i.label as NSString).size(withAttributes: [.font: font]).width
            if let value = i.value { w += 8 + (value as NSString).size(withAttributes: [.font: font]).width }
            if !i.shortcut.isEmpty { w += 16 + (i.shortcut.joined() as NSString).size(withAttributes: [.font: keyFont]).width }
            if i.kind == .sub { w += 18 }
            widest = max(widest, w)
        }
        return min(max(widest * 1.1 + 20 + 26 + 12 + 20, 180), 380)
    }
}
