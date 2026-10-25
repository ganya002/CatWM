import AppKit
import NativeTrafficLight
import SwiftUI

final class TabStripInput: NSView {
    private static let dragThreshold: CGFloat = 3
    private static let liftSlack: CGFloat = 5

    let model: TabStripModel
    private struct Press {
        let point: CGPoint
        let id: CGWindowID
        let grab: CGFloat
        let hold: CGPoint
        let onClose: Bool
    }

    private var press: Press?
    private var menuTab: CGWindowID?
    private var liftedTab: TabStripModel.Tab?
    private let host: NSView
    let lights = TrafficLights(buttons: TabStrip.lights)

    init(model: TabStripModel) {
        self.model = model
        host = NSHostingView(rootView: TabStripView(model: model))
        super.init(frame: .zero)
        addSubview(host)
        lights.onAction = { [weak self] light in
            let manager = WindowManager.shared
            let ids = self?.model.tabs.map(\.id) ?? []
            if light == .minimize { return manager.minimizeTabs(ids) }
            ids.forEach { _ = manager.closeWindow($0) }
        }
        addSubview(lights)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func layout() {
        super.layout()
        host.frame = bounds
        let size = TrafficLights.size(for: TabStrip.lights)
        lights.frame = NSRect(origin: NSPoint(x: TabStrip.lightsInset, y: model.style.corner + TabStrip.lightsInset),
                              size: size)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if lights.frame.contains(local) { return lights }
        return bar.contains(local) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        addTrackingArea(NSTrackingArea(rect: .zero, options: options, owner: self))
    }

    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseEntered(with event: NSEvent) { hover(event) }

    override func mouseExited(with _: NSEvent) {
        guard model.dragged == nil, menuTab == nil else { return }
        model.hovered = nil
        model.closeHovered = false
    }

    private var bar: NSRect { NSRect(x: 0, y: model.style.corner, width: bounds.width, height: TabStrip.height) }

    private func local(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func hover(_ event: NSEvent) {
        guard model.dragged == nil, menuTab == nil else { return }
        let point = local(event)
        guard point.y <= TabStrip.height, let index = model.index(at: point.x, width: bounds.width) else {
            model.hovered = nil
            return
        }
        let id = model.tabs[index].id
        if model.hovered != id { model.hovered = id }
        let onClose = model.closeRect(index, width: bounds.width).contains(point)
        if model.closeHovered != onClose { model.closeHovered = onClose }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { return openMenu(event) }
        let point = local(event)
        guard let index = model.index(at: point.x, width: bounds.width) else { return }
        let onClose = model.closeRect(index, width: bounds.width).contains(point)
        press = Press(point: NSEvent.mouseLocation, id: model.tabs[index].id,
                      grab: point.x - model.slotX(index, width: bounds.width),
                      hold: CGPoint(x: point.x + model.style.sideInset, y: point.y), onClose: onClose)
    }

    override func rightMouseDown(with event: NSEvent) { openMenu(event) }

    override func mouseDragged(with event: NSEvent) {
        guard let press, !press.onClose else { return }
        let now = NSEvent.mouseLocation
        if model.dragged == nil {
            guard hypot(now.x - press.point.x, now.y - press.point.y) >= Self.dragThreshold else { return }
            model.dragged = press.id
            model.hovered = nil
        }
        let strip = CGRect(x: 0, y: 0, width: bounds.width, height: TabStrip.height)
        let lifted = !strip.insetBy(dx: 0, dy: -Self.liftSlack).contains(local(event))
        if lifted {
            WindowManager.shared.dragTab(press.id, grab: press.hold, to: mouseLocation())
        } else if model.lifted {
            WindowManager.shared.cancelTabDrag(press.id)
        }
        let x = local(event).x - press.grab
        if model.lifted != lifted { lift(press.id, lifted, at: x) }
        guard let from = model.tabs.firstIndex(where: { $0.id == press.id }) else { return }
        let step = model.tabWidth(in: bounds.width)
        guard step > 0 else { return }
        let wanted = min(model.tabs.count - 1, max(0, Int(((x - TabStrip.lead) / step).rounded())))
        if wanted != from, !lifted {
            withAnimation(TabStrip.motion) {
                model.tabs.move(fromOffsets: [from], toOffset: wanted > from ? wanted + 1 : wanted)
            }
        }
        let index = model.tabs.firstIndex { $0.id == press.id } ?? from
        model.dragShift = x - model.slotX(index, width: bounds.width)
    }

    private func lift(_ id: CGWindowID, _ lifted: Bool, at x: CGFloat) {
        model.lifted = lifted
        withAnimation(TabStrip.motion) {
            if lifted, let from = model.tabs.firstIndex(where: { $0.id == id }) {
                liftedTab = model.tabs.remove(at: from)
            } else if !lifted, let tab = liftedTab {
                let step = max(0, bounds.width - TabStrip.lead) / CGFloat(model.tabs.count + 1)
                let wanted = step > 0 ? Int(((x - TabStrip.lead) / step).rounded()) : 0
                model.tabs.insert(tab, at: min(model.tabs.count, max(0, wanted)))
                liftedTab = nil
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        liftedTab = nil
        self.press = nil
        let manager = WindowManager.shared
        if model.dragged != nil {
            let lifted = model.lifted
            let index = model.tabs.firstIndex { $0.id == press.id }
            withAnimation(TabStrip.motion) {
                model.dragged = nil
                model.dragShift = 0
                model.lifted = false
            }
            if lifted {
                manager.dropTab(press.id, at: mouseLocation())
            } else if let index {
                manager.reorderTab(press.id, to: index)
            }
            hover(event)
            return
        }
        let point = local(event)
        if press.onClose, let index = model.index(at: point.x, width: bounds.width), model.tabs[index].id == press.id,
           model.closeRect(index, width: bounds.width).contains(point) {
            _ = manager.closeWindow(press.id)
        } else if !press.onClose {
            manager.selectTab(press.id)
        }
    }

    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let index = model.index(at: local(event).x, width: bounds.width) else { return }
        _ = WindowManager.shared.closeWindow(model.tabs[index].id)
    }

    private func openMenu(_ event: NSEvent) {
        guard model.dragged == nil, let index = model.index(at: local(event).x, width: bounds.width) else { return }
        let id = model.tabs[index].id
        let items = TabMenu.items(for: id)
        guard !items.isEmpty else { return }
        press = nil
        Popup.shared.context({ items }, onClose: { [weak self] in
            self?.menuTab = nil
            self?.model.hovered = nil
        })
        menuTab = id
        model.hovered = id
        model.closeHovered = false
    }

    func cancelDrag() {
        if let press, model.lifted {
            DispatchQueue.main.async { WindowManager.shared.cancelTabDrag(press.id) }
        }
        press = nil
        liftedTab = nil
        model.dragged = nil
        model.dragShift = 0
        model.lifted = false
        model.hovered = nil
    }
}
