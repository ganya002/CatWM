import AppKit
import CatWMKit
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
            guard let event = NSApp.currentEvent else { return nil }
            let controlClick = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            return event.type == .rightMouseDown || controlClick ? super.hitTest(point) : nil
        }
        override func rightMouseDown(with _: NSEvent) { action() }
        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { action() } else { super.mouseDown(with: event) }
        }
    }
}

struct SortScrollAccessor: NSViewRepresentable {
    let model: SortModel

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view, weak model] in model?.attach(view?.enclosingScrollView) }
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        DispatchQueue.main.async { [weak view, weak model] in
            model?.attach(view?.enclosingScrollView)
            model?.measureRow()
        }
    }
}
