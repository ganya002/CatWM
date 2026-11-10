import AppKit
import CatWMKit

final class TabStrips {
    static let shared = TabStrips()
    private var strips: [Int: Strip] = [:]
    private var previewing: Int?
    private var batchDepth = 0
    private var queuedUpdate = false
    private var queuedInstant = false
    private var queuedRestack = false

    func batch(_ changes: () -> Void) {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0 {
                let update = queuedUpdate, instant = queuedInstant, restack = queuedRestack
                queuedUpdate = false
                queuedInstant = false
                queuedRestack = false
                if update {
                    performUpdate(instant: instant, restackAll: restack)
                } else if restack {
                    self.restack()
                }
            }
        }
        changes()
    }

    func update(instant: Bool = false) {
        guard batchDepth == 0 else {
            queuedUpdate = true
            queuedInstant = instant
            return
        }
        performUpdate(instant: instant, restackAll: false)
    }

    private func performUpdate(instant: Bool, restackAll: Bool) {
        let manager = WindowManager.shared
        guard !strips.isEmpty || !manager.tabs.isEmpty else { return }
        let animate = !instant && manager.config.animate && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let focused = manager.focusedWindow()?.id
        var placed = Set<Int>()
        var placements: [(strip: Strip, active: CGWindowID)] = []
        var hidden: [TabStripReveal.Target] = []
        if manager.tilingEnabled, manager.isStarted, manager.config.features.contains(.tabStrips) {
            for screen in Screen.all() {
                for id in manager.tiled(on: screen) {
                    guard let group = manager.tabs.group(of: id), let target = manager.targets[id],
                          !placed.contains(group.id), !manager.tabUI.minimizingTabs.contains(group.id) else { continue }
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
                    placements.append((strip, group.active))
                }
            }
        }
        TabStripReveal.shared.watch(hidden)
        let live = Set(manager.tabs.groups.filter { group in
            let active = group.active
            return !manager.model.isShown(manager.workspaceOf[active])
                || (!manager.present.contains(active) && manager.windows[active]?.minimized == false)
        }.map(\.id))
        for (key, strip) in strips where !placed.contains(key) {
            if manager.tilingEnabled, live.contains(key) { continue }
            strip.close()
            strips[key] = nil
        }
        place(placements, excluding: placed, restackAll: restackAll)
    }

    private func place(_ placements: [(strip: Strip, active: CGWindowID)], excluding placed: Set<Int>,
                       restackAll: Bool) {
        guard !placements.isEmpty || (restackAll && !strips.isEmpty) else { return }
        var stack = TabStripStack(windows: Strip.stack())
        for (strip, active) in placements { strip.place(above: active, in: &stack) }
        if restackAll {
            for (key, strip) in strips where !placed.contains(key) { strip.restack(in: &stack) }
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

    var isPreviewing: Bool { previewing != nil }

    func restack() {
        guard batchDepth == 0 else { queuedRestack = true; return }
        guard !strips.isEmpty else { return }
        var stack = TabStripStack(windows: Strip.stack())
        for strip in strips.values { strip.restack(in: &stack) }
    }

    func shift(_ group: Int, by offset: CGVector) {
        strips[group]?.shift(by: offset)
    }
}

struct TabStripStack {
    enum Placement: Equatable {
        case above(CGWindowID)
        case below(CGWindowID)
    }

    private(set) var windows: [CGWindowID]

    mutating func place(_ panel: CGWindowID, below members: [CGWindowID], fallback: CGWindowID? = nil)
        -> Placement? {
        guard let top = windows.first(where: members.contains) ?? fallback else { return nil }
        guard let index = windows.firstIndex(of: top) else { return .below(top) }
        guard let under = windows.dropFirst(index + 1).first(where: { $0 != panel }),
              windows.dropFirst(index + 1).first != panel else { return nil }
        windows.removeAll { $0 == panel }
        guard let destination = windows.firstIndex(of: under) else { return nil }
        windows.insert(panel, at: destination)
        return .above(under)
    }
}

final class TabStripFollow {
    private struct Anchor {
        let group: Int
        let offset: CGVector
        let cursor: CGPoint
        let lowest: CGFloat
    }

    static let shared = TabStripFollow()
    private var anchor: Anchor?
    private var monitors: [Any] = []

    func follow(_ group: Int, at offset: CGVector, lowest: CGFloat) {
        anchor = Anchor(group: group, offset: offset, cursor: mouseLocation(), lowest: lowest)
        TabStrips.shared.shift(group, by: offset)
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDragged]
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.moved()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.moved() }
        monitors = [local, global].compactMap(\.self)
    }

    func end() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        anchor = nil
    }

    private func moved() {
        guard let anchor else { return }
        let cursor = mouseLocation()
        let dy = max(anchor.lowest, anchor.offset.dy + cursor.y - anchor.cursor.y)
        TabStrips.shared.shift(anchor.group, by: CGVector(dx: anchor.offset.dx + cursor.x - anchor.cursor.x, dy: dy))
    }
}
