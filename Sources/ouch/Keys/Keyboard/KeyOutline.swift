import AppKit
import SwiftUI
import MacKeysCore
import MacKeysUI

struct KeyOutline: Shape {
    let cap: KeyCap

    func path(in rect: CGRect) -> Path {
        let s = rect.width / CGFloat(cap.w)
        return MacKeyCap.outline(of: cap).applying(CGAffineTransform(scaleX: s, y: s)).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
