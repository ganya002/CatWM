import AppKit
import NativeTrafficLight
import SwiftUI

final class TabStrips {
    static let shared = TabStrips()
    private var strips: [Int: Strip] = [:]

    func update(instant: Bool = false) {
        let manager = WindowManager.shared
        guard !strips.isEmpty || !manager.tabs.isEmpty else { return }
        let animate = !instant && manager.config.animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let focused = manager.focusedWindow()?.id
        var placed = Set<Int>()
        var hidden: [TabStripReveal.Target] = []
        if manager.tilingEnabled {
            for screen in Screen.all() {
                for id in manager.tiled(on: screen) {
                    guard let group = manager.tabs.group(of: id), let target = manager.targets[id],
                          !placed.contains(group.id), !manager.minimizingTabs.contains(group.id) else { continue }
                    placed.insert(group.id)
                    let strip = strips[group.id] ?? Strip()
                    strips[group.id] = strip
                    if manager.config.autoHideTabStrip, let window = manager.windows[group.active] {
                        let revealed = TabStripReveal.shared.revealed == group.id
                        let top = revealed ? TabStrip.height : 0
                        hidden.append(.init(group: group.id, slot: CGRect(x: target.minX, y: target.minY - top,
                                                                          width: target.width,
                                                                          height: target.height + top),
                                            window: window))
                        if !revealed {
                            strip.hide()
                            continue
                        }
                    }
                    strip.show(group, above: target,
                               focused: focused.map(group.members.contains) ?? false,
                               duration: animate ? manager.config.animationDuration : 0)
                }
            }
        }
        TabStripReveal.shared.watch(hidden)
        let live = Set(manager.tabs.groups.filter { !manager.model.isShown(manager.workspaceOf[$0.active]) }.map(\.id))
        for (key, strip) in strips where !placed.contains(key) {
            if manager.tilingEnabled, live.contains(key) { continue }
            strip.close()
            strips[key] = nil
        }
    }

    private final class Strip {
        private let panel = OuchPanel(role: .attached)
        private let model = TabStripModel()
        private let view: TabStripInput
        private var target: NSRect?
        private var anchor: CGWindowID = 0
        private var hidden = false

        init() {
            view = TabStripInput(model: model)
            panel.contentView = view
        }

        func show(_ group: TabGroups.Group, above slot: CGRect, focused: Bool, duration: Double) {
            hidden = false
            let manager = WindowManager.shared
            let tabs = group.members.compactMap { id in
                manager.windows[id].map { window in
                    TabStripModel.Tab(id: id, title: Self.title(of: window), pid: window.pid)
                }
            }
            if model.dragged == nil, model.tabs != tabs { model.tabs = tabs }
            if model.active != group.active { model.active = group.active }
            if model.focused != focused { model.focused = focused }
            view.lights.isActive = focused
            let frame = Self.frame(above: slot)
            if frame != target || !panel.isVisible || panel.alphaValue < 1 {
                let wasVisible = panel.isVisible
                target = frame
                if wasVisible, duration > 0 {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = duration
                        context.timingFunction = Motion.Curve.easeOut
                        panel.animator().setFrame(frame, display: true)
                    }
                } else {
                    panel.setFrame(frame, display: true)
                }
                if !wasVisible || panel.alphaValue < 1 {
                    if !wasVisible { panel.alphaValue = 0 }
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = Theme.medium
                        context.timingFunction = Motion.Curve.easeOut
                        panel.animator().alphaValue = 1
                    }
                }
            }
            panel.order(.below, relativeTo: Int(Self.lowest(of: group)))
            if anchor != group.active || !wasOnSpace(of: group.active) { moveToSpace(of: group.active) }
            anchor = group.active
        }

        func hide() {
            guard panel.isVisible, !hidden else { return }
            hidden = true
            view.cancelDrag()
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = Theme.medium
                context.timingFunction = Motion.Curve.easeOut
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.hidden else { return }
                self.panel.orderOut(nil)
                self.target = nil
            })
        }

        func close() {
            view.cancelDrag()
            panel.orderOut(nil)
            target = nil
        }

        private func wasOnSpace(of id: CGWindowID) -> Bool {
            let mine = Spaces.of(window: CGWindowID(panel.windowNumber))
            return !mine.isEmpty && Set(mine) == Set(Spaces.of(window: id))
        }

        private func moveToSpace(of id: CGWindowID) {
            guard let space = Spaces.of(window: id).first, panel.windowNumber > 0 else { return }
            let number = CGWindowID(panel.windowNumber)
            guard Spaces.of(window: number) != [space] else { return }
            Spaces.move(window: number, to: space) { moved in
                if !moved { Log.debug("tabs: could not move a tab strip to Desktop \(space)") }
            }
        }

        private static func lowest(of group: TabGroups.Group) -> CGWindowID {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            let ids = (list as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
            return ids.last(where: group.members.contains) ?? group.active
        }

        private static func title(of window: Window) -> String {
            if let title = window.title, !title.isEmpty { return title }
            return NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "Window"
        }

        private static func frame(above slot: CGRect) -> NSRect {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return NSRect(x: slot.minX + TabStrip.inset, y: primaryHeight - slot.minY,
                          width: max(0, slot.width - TabStrip.inset * 2), height: TabStrip.height).integral
        }
    }
}

private final class TabStripInput: NSView {
    private static let dragThreshold: CGFloat = 3
    private static let liftDistance: CGFloat = 24

    let model: TabStripModel
    private struct Press {
        let point: CGPoint
        let id: CGWindowID
        let grab: CGFloat
        let onClose: Bool
    }

    private var press: Press?
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
        lights.frame = NSRect(origin: NSPoint(x: TabStrip.lightsInset, y: TabStrip.lightsInset), size: size)
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if lights.frame.contains(local) { return lights }
        return bounds.contains(local) ? self : nil
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
        guard model.dragged == nil else { return }
        model.hovered = nil
        model.closeHovered = false
    }

    private func local(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func hover(_ event: NSEvent) {
        guard model.dragged == nil else { return }
        let point = local(event)
        guard let index = model.index(at: point.x, width: bounds.width) else {
            model.hovered = nil
            return
        }
        let id = model.tabs[index].id
        if model.hovered != id { model.hovered = id }
        let onClose = model.closeRect(index, width: bounds.width).contains(point)
        if model.closeHovered != onClose { model.closeHovered = onClose }
    }

    override func mouseDown(with event: NSEvent) {
        let point = local(event)
        guard let index = model.index(at: point.x, width: bounds.width) else { return }
        let onClose = model.closeRect(index, width: bounds.width).contains(point)
        press = Press(point: NSEvent.mouseLocation, id: model.tabs[index].id,
                      grab: point.x - model.slotX(index, width: bounds.width), onClose: onClose)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, !press.onClose else { return }
        let now = NSEvent.mouseLocation
        if model.dragged == nil {
            guard hypot(now.x - press.point.x, now.y - press.point.y) >= Self.dragThreshold else { return }
            model.dragged = press.id
            model.hovered = nil
        }
        let lifted = abs(now.y - press.point.y) > Self.liftDistance
        if model.lifted != lifted { model.lifted = lifted }
        let x = local(event).x - press.grab
        guard let from = model.tabs.firstIndex(where: { $0.id == press.id }) else { return }
        let step = model.tabWidth(in: bounds.width)
        guard step > 0 else { return }
        let wanted = min(model.tabs.count - 1, max(0, Int(((x - TabStrip.lead) / step).rounded())))
        if wanted != from, !lifted {
            withAnimation(Motion.snap) {
                model.tabs.move(fromOffsets: [from], toOffset: wanted > from ? wanted + 1 : wanted)
            }
        }
        let index = model.tabs.firstIndex { $0.id == press.id } ?? from
        model.dragShift = x - model.slotX(index, width: bounds.width)
    }

    override func mouseUp(with event: NSEvent) {
        guard let press else { return }
        self.press = nil
        let manager = WindowManager.shared
        if model.dragged != nil {
            let lifted = model.lifted
            let index = model.tabs.firstIndex { $0.id == press.id }
            withAnimation(Motion.snap) {
                model.dragged = nil
                model.dragShift = 0
                model.lifted = false
            }
            if lifted {
                manager.untab(press.id, droppedAt: mouseLocation())
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

    func cancelDrag() {
        press = nil
        model.dragged = nil
        model.dragShift = 0
        model.lifted = false
        model.hovered = nil
    }
}
