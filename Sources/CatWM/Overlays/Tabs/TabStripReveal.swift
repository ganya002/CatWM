import AppKit
import CatWMKit

final class TabStripReveal {
    struct Target {
        let group: Int
        let slot: CGRect
        let window: Window
    }

    static let shared = TabStripReveal()
    private static let reach: CGFloat = 60
    private static let lead: CGFloat = 10
    private static let lightsMargin: CGFloat = 20
    private static let linger: TimeInterval = 0.3

    private(set) var revealed: Int?
    private var targets: [Target] = []
    private var bars: [CGWindowID: TitleBar] = [:]
    private var reading: Set<CGWindowID> = []
    private let titleBars = TitleBarCache()
    private var monitors: [Any] = []
    private var hideWork: DispatchWorkItem?
    private var last: CGPoint?

    func watch(_ targets: [Target]) {
        self.targets = targets
        guard !targets.isEmpty else { return stop() }
        let ids = Set(targets.map(\.window.id))
        bars = bars.filter { ids.contains($0.key) }
        targets.forEach { readTitleBar(of: $0.window) }
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.moved()
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.moved() }
        monitors = [local, global].compactMap(\.self)
    }

    private func readTitleBar(of window: Window) {
        let id = window.id
        guard !reading.contains(id), !WindowManager.shared.animator.isBusy(id) else { return }
        reading.insert(id)
        titleBars.titleBar(of: window, on: WindowManager.shared.scanner) { [weak self] bar in
            guard let self else { return }
            reading.remove(id)
            if let bar, targets.contains(where: { $0.window.id == id }) { bars[id] = bar }
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hideWork?.cancel()
        hideWork = nil
        revealed = nil
        bars = [:]
        last = nil
    }

    private func moved() {
        let point = NSEvent.mouseLocation
        let cursor = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        let heading = last.map { CGVector(dx: cursor.x - $0.x, dy: cursor.y - $0.y) }
        last = cursor
        let hit = targets.first { target in
            if bars[target.window.id] == nil { readTitleBar(of: target.window) }
            return Self.reveals(cursor, slot: target.slot, bar: bars[target.window.id],
                                revealed: revealed == target.group, heading: heading)
        }
        if let hit {
            hideWork?.cancel()
            hideWork = nil
            reveal(hit.group)
        } else if revealed != nil, hideWork == nil {
            let work = DispatchWorkItem { [weak self] in
                self?.hideWork = nil
                self?.reveal(nil)
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.linger, execute: work)
        }
    }

    static func reveals(_ point: CGPoint, slot: CGRect, bar: TitleBar?, revealed: Bool,
                        heading: CGVector? = nil) -> Bool {
        guard point.x >= slot.minX, point.x <= slot.maxX, point.y >= slot.minY - reach else { return false }
        if revealed { return point.y <= slot.minY + TabStrip.height }
        guard point.y >= slot.minY else { return true }
        let margin = -lightsMargin
        if let lights = bar?.lights?.offsetBy(dx: slot.minX, dy: slot.minY).insetBy(dx: margin, dy: margin),
           lights.contains(point) || aims(heading, from: point, at: lights) {
            return false
        }
        return point.y <= slot.minY + (bar?.clearTop ?? lead)
    }

    static func aims(_ heading: CGVector?, from point: CGPoint, at target: CGRect) -> Bool {
        guard let heading, heading.dx != 0 || heading.dy != 0 else { return false }
        var near: CGFloat = 0, far = CGFloat.infinity
        for (start, step, low, high) in [(point.x, heading.dx, target.minX, target.maxX),
                                         (point.y, heading.dy, target.minY, target.maxY)] {
            if step == 0 {
                guard start >= low, start <= high else { return false }
                continue
            }
            let one = (low - start) / step, two = (high - start) / step
            near = max(near, min(one, two))
            far = min(far, max(one, two))
        }
        return near <= far
    }

    private func reveal(_ group: Int?) {
        guard group != revealed else { return }
        revealed = group
        WindowManager.shared.refresh()
    }
}
