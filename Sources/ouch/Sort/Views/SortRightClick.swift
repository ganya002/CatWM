import AppKit
import SwiftUI

struct SortRightClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context _: Context) -> NSView {
        let view = RightClickView()
        view.action = action
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) { (view as? RightClickView)?.action = action }

    final class RightClickView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with _: NSEvent) { action() }
    }
}
