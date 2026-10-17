import AppKit
import SwiftUI

final class TooltipTrackingView: PassThroughView {
    var text = ""
    var chords: [[String]] = []
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { Tooltip.shared.hover(self, text: text, chords: chords) }
    override func mouseExited(with event: NSEvent) { Tooltip.shared.leave(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Tooltip.shared.leave(self) }
    }
}
