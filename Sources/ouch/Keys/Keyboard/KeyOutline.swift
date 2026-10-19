import AppKit
import MacKeysCore
import MacKeysUI
import SwiftUI

struct KeyOutline: Shape {
    let cap: KeyCap

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / CGFloat(cap.w)
        return MacKeyCap.outline(of: cap).applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
