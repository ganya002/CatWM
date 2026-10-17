import AppKit
import SwiftUI

struct SortRightClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let v = RightClickView()
        v.action = action
        return v
    }

    func updateNSView(_ v: NSView, context: Context) { (v as? RightClickView)?.action = action }

    final class RightClickView: NSView {
        var action: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with event: NSEvent) { action() }
    }
}
