import AppKit

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
                    placements.append((strip, group.active))
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
