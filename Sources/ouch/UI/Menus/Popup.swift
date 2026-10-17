import AppKit
import SwiftUI

final class Popup: NSObject, NSWindowDelegate {
    static let shared = Popup()

    private struct Entry {
        let panel: OuchPanel
        let generation: Int
        weak var parent: NSWindow?
        var onClose: (() -> Void)?
        let keys: (NSEvent) -> Bool
    }

    private var stack: [Entry] = []
    private let dismiss = DismissMonitor()
    private static var margin: CGFloat { Elevation.popover.room }

    var isOpen: Bool { !stack.isEmpty }
    private(set) var generation = 0

    func menu(_ items: @escaping () -> [MenuItem], from anchor: NSRect, minWidth: CGFloat = 0, onClose: (() -> Void)? = nil) {
        let model = MenuModel()
        model.searchable = false
        model.source = items
        model.rebuild()
        let width = max(minWidth, MenuItem.fitWidth(model.items))

        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, m = Self.margin
        let subs = 2 * (Theme.submenuWidth + 48)
        let left = min(max(anchor.minX - 4, v.minX + 8), v.maxX - width - 8)
        model.opensLeft = left + width + subs > v.maxX - 8
        let below = anchor.minY - v.minY, above = v.maxY - anchor.maxY
        let fromBottom = below < 260 && above > below
        let height = min(fromBottom ? above : below, 820)
        let x = model.opensLeft ? left - subs - m : left - m
        let frame = fromBottom
            ? NSRect(x: x, y: anchor.maxY + 4 - m, width: width + subs + 2 * m, height: height)
            : NSRect(x: x, y: anchor.minY - 4 + m - height, width: width + subs + 2 * m, height: height)
        let view = MenuRoot(model: model, rootX: model.opensLeft ? subs + m : m, top: m, size: frame.size,
                            rootWidth: width, fromBottom: fromBottom)
        let g = generation + 1
        model.close = { [weak self] in self?.close(generation: g) }
        show(AnyView(view), frame: frame, onClose: onClose) { e in Self.menuKey(e, model) }
        DispatchQueue.main.async { withAnimation(Motion.easeOut) { model.appeared = true } }
    }

    func popover<Content: View>(from anchor: NSRect, onClose: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        let host = NSHostingView(rootView: content().surface(.md, glass: true).padding(Self.margin)
            .font(Theme.body()).foregroundStyle(Theme.ink).tint(Theme.accent))
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame, m = Self.margin
        let x = min(max(anchor.minX - 4 - m, v.minX + 8 - m), v.maxX - size.width + m - 8)
        let fitsBelow = anchor.minY - 4 - (size.height - 2 * m) > v.minY
        let y = fitsBelow ? anchor.minY - 4 + m - size.height : anchor.maxY + 4 - m
        show(AnyView(host.rootView), frame: NSRect(x: x, y: y, width: size.width, height: size.height), onClose: onClose) { _ in false }
    }

    private func show(_ view: AnyView, frame: NSRect, onClose: (() -> Void)?, keys: @escaping (NSEvent) -> Bool) {
        let key = NSApp.keyWindow
        if !stack.contains(where: { $0.panel === key }) { closeAll() }
        generation += 1
        let p = makePanel()
        let g = generation
        p.onClose = { [weak self] in self?.close(generation: g) }
        stack.append(Entry(panel: p, generation: generation, parent: key, onClose: onClose, keys: keys))
        p.contentView = OuchHostingView(rootView: view)
        p.setFrame(frame, display: true)
        p.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close(generation g: Int) {
        if let i = stack.firstIndex(where: { $0.generation == g }) { close(from: i) }
    }

    func close() { if !stack.isEmpty { close(from: stack.count - 1) } }

    func closeAll() { close(from: 0) }

    private func close(from index: Int) {
        while stack.count > index {
            var entry = stack.removeLast()
            let panel = entry.panel
            let done = entry.onClose
            entry.onClose = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                panel.contentView = nil
            })
            if let parent = entry.parent, parent.isVisible { parent.makeKey() }
            done?()
        }
        if stack.isEmpty { dismiss.stop() }
    }

    private func makePanel() -> OuchPanel {
        let p = OuchPanel(role: .menu)
        p.delegate = self
        return p
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let resigned = notification.object as? NSWindow,
              stack.contains(where: { $0.panel === resigned }) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let i = self.stack.firstIndex(where: { $0.panel === resigned }) else { return }
            if self.stack.contains(where: { $0.panel.isKeyWindow }) { return }
            self.close(from: i)
        }
    }

    private func installMonitors() {
        dismiss.start(keeps: { [weak self] w in
            guard let self, let i = stack.firstIndex(where: { $0.panel === w }) else { return false }
            if i < stack.count - 1 { close(from: i + 1) }
            return true
        }, swallowsClick: true, key: { [weak self] e in
            guard let self, let top = stack.last, top.panel.isKeyWindow else { return false }
            if e.keyCode == 53 { if !top.keys(e) { close() }; return true }
            return top.keys(e)
        }, close: { [weak self] in self?.closeAll() })
    }

    private static func menuKey(_ e: NSEvent, _ model: MenuModel) -> Bool {
        switch e.keyCode {
        case 126: model.move(-1)
        case 125: model.move(1)
        case 124: model.openHighlighted()
        case 123: _ = model.back()
        case 36, 76: model.runHighlighted()
        case 53: return model.back()
        default: return false
        }
        return true
    }
}
