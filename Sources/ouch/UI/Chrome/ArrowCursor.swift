import AppKit
import SwiftUI

final class ArrowCursor: NSResponder {
    private weak var view: NSView?
    private static var key = 0

    static func keep(in view: NSView) {
        let keeper = ArrowCursor()
        keeper.view = view
        objc_setAssociatedObject(view, &key, keeper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                            owner: keeper))
    }

    override func mouseEntered(with event: NSEvent) { update(event) }
    override func mouseMoved(with event: NSEvent) { update(event) }

    private func update(_ e: NSEvent) {
        let current = NSCursor.current
        guard current == NSCursor.iBeam || current == NSCursor.iBeamCursorForVerticalLayout,
              let content = view?.window?.contentView else { return }
        var hit = content.hitTest(content.superview?.convert(e.locationInWindow, from: nil) ?? e.locationInWindow)
        while let v = hit {
            if v is NSText || v is NSTextField { return }
            hit = v.superview
        }
        NSCursor.arrow.set()
    }
}
