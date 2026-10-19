import AppKit
import SwiftUI

class OuchHostingView<Content: View>: NSHostingView<Content> {
    private var keepsArrow = false

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !keepsArrow else { return }
        keepsArrow = true
        ArrowCursor.keep(in: self)
    }
}
