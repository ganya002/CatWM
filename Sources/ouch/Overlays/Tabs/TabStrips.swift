import AppKit
import NativeTrafficLight
import SwiftUI

final class TabStrips {
    static let shared = TabStrips()
    private var strips: [Int: Strip] = [:]
    private var previewing: Int?

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

    func preview(_ window: Window, at point: CGPoint) -> Bool {
        let hit = strips.first { key, strip in
            WindowManager.shared.tabs.groups.first { $0.id == key }?.members.contains(window.id) == false
                && strip.contains(point)
        }
        if let previewing, previewing != hit?.key { _ = strips[previewing]?.endPreview(of: window.id) }
        previewing = hit?.key
        hit?.value.preview(window, at: point)
        return hit != nil
    }

    func endPreview(of id: CGWindowID) -> (group: Int, index: Int)? {
        guard let group = previewing else { return nil }
        previewing = nil
        return strips[group]?.endPreview(of: id).map { (group, $0) }
    }

    func shift(_ group: Int, by offset: CGVector) {
        strips[group]?.shift(by: offset)
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

        func contains(_ point: CGPoint) -> Bool {
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            return panel.isVisible && panel.alphaValue > 0
                && panel.frame.contains(NSPoint(x: point.x, y: primaryHeight - point.y))
        }

        func preview(_ window: Window, at point: CGPoint) {
            let x = point.x - panel.frame.minX
            let width = panel.frame.width
            if !model.tabs.contains(where: { $0.id == window.id }) {
                let step = max(0, width - TabStrip.lead) / CGFloat(model.tabs.count + 1)
                let wanted = step > 0 ? Int(((x - TabStrip.lead) / step).rounded(.down)) : 0
                withAnimation(Motion.snap) {
                    model.tabs.insert(.init(id: window.id, title: Self.title(of: window), pid: window.pid),
                                      at: min(model.tabs.count, max(0, wanted)))
                }
                model.dragged = window.id
                model.hovered = nil
            }
            guard let from = model.tabs.firstIndex(where: { $0.id == window.id }) else { return }
            let step = model.tabWidth(in: width)
            guard step > 0 else { return }
            let grab = x - step / 2
            let wanted = min(model.tabs.count - 1, max(0, Int(((grab - TabStrip.lead) / step).rounded())))
            if wanted != from {
                withAnimation(Motion.snap) {
                    model.tabs.move(fromOffsets: [from], toOffset: wanted > from ? wanted + 1 : wanted)
                }
            }
            model.dragShift = grab - model.slotX(wanted, width: width)
        }

        func endPreview(of id: CGWindowID) -> Int? {
            guard let index = model.tabs.firstIndex(where: { $0.id == id }) else { return nil }
            withAnimation(Motion.snap) {
                model.tabs.remove(at: index)
                model.dragged = nil
                model.dragShift = 0
            }
            return index
        }

        func shift(by offset: CGVector) {
            guard let target, panel.isVisible else { return }
            panel.setFrameOrigin(NSPoint(x: target.minX + offset.dx, y: target.minY - offset.dy))
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
