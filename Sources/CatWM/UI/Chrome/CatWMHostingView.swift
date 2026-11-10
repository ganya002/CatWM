import AppKit
import CatWMKit
import SwiftUI

class CatWMHostingView<Content: View>: NSHostingView<Content> {
    private var keepsArrow = false

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !keepsArrow else { return }
        keepsArrow = true
        ArrowCursor.keep(in: self)
    }
}

final class ArrowCursor: NSResponder {
    private weak var view: NSView?
    private static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    static func keep(in view: NSView) {
        let keeper = ArrowCursor()
        keeper.view = view
        objc_setAssociatedObject(view, key, keeper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: keeper))
    }

    override func mouseEntered(with event: NSEvent) { update(event) }
    override func mouseMoved(with event: NSEvent) { update(event) }

    private func update(_ event: NSEvent) {
        let current = NSCursor.current
        guard current == NSCursor.iBeam || current == NSCursor.iBeamCursorForVerticalLayout,
              let content = view?.window?.contentView else { return }
        let location = event.locationInWindow
        var hit = content.hitTest(content.superview?.convert(location, from: nil) ?? location)
        while let view = hit {
            if view is NSText || view is NSTextField { return }
            hit = view.superview
        }
        NSCursor.arrow.set()
    }
}
