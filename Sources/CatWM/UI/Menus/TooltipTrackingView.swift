import AppKit
import SwiftUI

final class TooltipTrackingView: PassThroughView {
    var text = ""
    var chords: [[String]] = []
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let tracking = NSTrackingArea(rect: .zero, options: options, owner: self)
        addTrackingArea(tracking)
        area = tracking
    }

    override func mouseEntered(with _: NSEvent) { Tooltip.shared.hover(self, text: text, chords: chords) }
    override func mouseExited(with _: NSEvent) { Tooltip.shared.leave(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { Tooltip.shared.leave(self) }
    }
}
