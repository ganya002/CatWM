import AppKit
import CatWMKit
import SwiftUI

final class ImpactView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not supported") }

    func fire(at center: NSPoint) {
        guard let root = layer else { return }
        Motion.impact(on: root, center: center, bounds: bounds)
    }
}
