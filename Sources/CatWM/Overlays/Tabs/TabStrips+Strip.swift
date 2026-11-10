import AppKit
import CatWMKit
import NativeTrafficLight
import SwiftUI

extension TabStrips {
    final class Strip {
        private let panel = CatWMPanel(role: .attached)
        private let model = TabStripModel()
        private let view: TabStripInput
        private var target: NSRect?
        private var anchor: CGWindowID = 0
        private var members: [CGWindowID] = []
        private var hidden = false
        private var shifted = false
        private let glide = PanelGlide()

        init() {
            view = TabStripInput(model: model)
            panel.contentView = view
        }

        func show(_ group: TabGroups.Group, above slot: CGRect, focused: Bool, duration: Double) {
            hidden = false
            let manager = WindowManager.shared
            let tabs = group.members.compactMap { id in
                manager.windows[id].map { window in
                    TabStripModel.Tab(id: id, title: Self.title(of: window), pid: window.pid,
                                      badge: Notifications.shared.badge(for: id))
                }
            }
            if model.dragged == nil, model.tabs != tabs { model.tabs = tabs }
            if model.active != group.active { model.active = group.active }
            if model.focused != focused { model.focused = focused }
            view.lights.isActive = focused
            let frame = Self.frame(above: slot)
            if frame != target || shifted || !panel.isVisible || panel.alphaValue < 1 {
                let wasVisible = panel.isVisible
                target = frame
                shifted = false
                if wasVisible, duration > 0 {
                    var spec = MotionSpec(WindowManager.shared.config)
                    spec.duration = duration
                    glide.to(frame, on: panel, spec: spec)
                } else {
                    glide.stop()
                    panel.setFrame(frame, display: true)
                }
                if !wasVisible || panel.alphaValue < 1 {
                    if !wasVisible { panel.alphaValue = 0 }
                    Motion.fade(panel, to: 1, duration: TabStrip.fade(Theme.medium))
                }
            }
            members = group.members
        }

        func place(above active: CGWindowID, in stack: inout TabStripStack) {
            restack(in: &stack, else: active)
            if anchor != active || !wasOnSpace(of: active) { moveToSpace(of: active) }
            anchor = active
        }

        func contains(_ point: CGPoint) -> Bool {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let bar = NSRect(x: panel.frame.minX, y: panel.frame.minY + TabStrip.corner,
                             width: panel.frame.width, height: TabStrip.height)
            return panel.isVisible && panel.alphaValue > 0
                && bar.contains(NSPoint(x: point.x, y: primaryHeight - point.y))
        }

        func preview(_ window: Window, at point: CGPoint) {
            let x = point.x - panel.frame.minX
            let width = panel.frame.width
            if !model.tabs.contains(where: { $0.id == window.id }) {
                let wanted = model.slot(at: x, width: width, extra: 1, rounding: .down)
                withAnimation(Motion.tabStrip) {
                    model.tabs.insert(.init(id: window.id, title: Self.title(of: window), pid: window.pid), at: wanted)
                }
                model.dragged = window.id
                model.hovered = nil
            }
            guard let from = model.tabs.firstIndex(where: { $0.id == window.id }) else { return }
            let step = model.tabWidth(in: width)
            guard step > 0 else { return }
            let grab = x - step / 2
            let wanted = model.slot(at: grab, width: width)
            if wanted != from {
                withAnimation(Motion.tabStrip) {
                    model.tabs.move(fromOffsets: [from], toOffset: wanted > from ? wanted + 1 : wanted)
                }
            }
            model.dragShift = grab - model.slotX(wanted, width: width)
        }

        func endPreview(of id: CGWindowID) -> Int? {
            guard let index = model.tabs.firstIndex(where: { $0.id == id }) else { return nil }
            withAnimation(Motion.tabStrip) {
                model.tabs.remove(at: index)
                model.dragged = nil
                model.dragShift = 0
            }
            return index
        }

        func shift(by offset: CGVector) {
            guard let target, panel.isVisible else { return }
            glide.stop()
            shifted = true
            panel.setFrameOrigin(NSPoint(x: target.minX + offset.dx, y: target.minY - offset.dy))
        }

        func hide() {
            guard panel.isVisible, !hidden else { return }
            hidden = true
            view.cancelDrag()
            Motion.fade(panel, to: 0, duration: TabStrip.fade(Theme.medium)) { [weak self] in
                guard let self, self.hidden else { return }
                self.panel.orderOut(nil)
                self.target = nil
            }
        }

        func close() {
            glide.stop()
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

        func restack(in stack: inout TabStripStack, else fallback: CGWindowID? = nil) {
            guard target != nil, !hidden else { return }
            switch stack.place(CGWindowID(panel.windowNumber), below: members, fallback: fallback) {
            case .above(let window): panel.order(.above, relativeTo: Int(window))
            case .below(let window): panel.order(.below, relativeTo: Int(window))
            case nil: break
            }
        }

        static func stack() -> [CGWindowID] {
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            return (list as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
        }

        private static func title(of window: Window) -> String {
            if let title = window.title, !title.isEmpty { return title }
            return NSRunningApplication(processIdentifier: window.pid)?.localizedName ?? "Window"
        }

        private static func frame(above slot: CGRect) -> NSRect {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return NSRect(x: slot.minX, y: primaryHeight - slot.minY - TabStrip.corner,
                          width: max(0, slot.width), height: TabStrip.panelHeight).integral
        }
    }
}
