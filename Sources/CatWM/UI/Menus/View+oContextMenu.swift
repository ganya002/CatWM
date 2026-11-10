import AppKit
import CatWMKit
import SwiftUI

extension View {
    func oContextMenu(opened: @escaping (Bool) -> Void = { _ in },
                      items: @escaping () -> [MenuItem]) -> some View {
        overlay(ContextClickView(opened: opened, items: items))
    }
}

private struct ContextClickView: NSViewRepresentable {
    let opened: (Bool) -> Void
    let items: () -> [MenuItem]

    func makeNSView(context _: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context _: Context) {
        view.opened = opened
        view.items = items
    }

    final class ClickView: NSView {
        var opened: (Bool) -> Void = { _ in }
        var items: () -> [MenuItem] = { [] }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let control = event.type == .leftMouseDown && event.modifierFlags.contains(.control)
            return event.type == .rightMouseDown || control ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with _: NSEvent) { open() }

        override func mouseDown(with _: NSEvent) { open() }

        private func open() {
            guard items().contains(where: { !$0.hidden && $0.kind != .separator }) else { return }
            Popup.shared.context(items, onClose: { [opened] in opened(false) })
            opened(true)
        }
    }
}
