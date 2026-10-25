import AppKit
import SwiftUI

class CatWMHostingView<Content: View>: NSHostingView<Content> {
    private var arrowCursor: ArrowCursor?

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, arrowCursor == nil else { return }
        arrowCursor = ArrowCursor(keeping: self)
    }
}

final class ArrowCursor: NSResponder {
    private weak var view: NSView?

    init(keeping view: NSView) {
        self.view = view
        super.init()
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

    required init?(coder _: NSCoder) { nil }

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
