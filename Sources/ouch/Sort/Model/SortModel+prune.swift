import AppKit
import SwiftUI

extension SortModel {
    func prune(alive: Set<CGWindowID>) {
        for k in plans.keys {
            guard var p = plans[k] else { continue }
            let gone = p.items.keys.filter { !alive.contains($0) }
            guard !gone.isEmpty else { continue }
            for id in gone { p.detach(id); p.items[id] = nil }
            plans[k] = p
            if let s = selected, gone.contains(s) { selected = nil }
            if let h = hover, gone.contains(h) { hover = nil }
        }
    }

    func target() -> CGWindowID? { hover ?? selected }

    func place(_ id: CGWindowID, inLane i: Int, at index: Int? = nil) {
        edit { $0.place(id, inLane: i, at: index) }
        show(id)
    }

    func markClosing(_ id: CGWindowID) {
        edit { $0.markClosing(id) }
        show(id)
    }

    func toggleClose(_ id: CGWindowID) { plan.isClosing(id) ? restore(id) : markClosing(id) }

    func send(_ id: CGWindowID, toWorkspace ws: String) {
        if let i = plan.lanes.firstIndex(where: { $0.ws == ws }) {
            place(id, inLane: i)
        } else if let new = addLane(focus: false, named: ws) {
            place(id, inLane: new)
        }
    }

    @discardableResult
    func addLane(focus: Bool, named: String? = nil) -> Int? {
        var index: Int?
        let other = reserved()
        edit { index = $0.addLane(layout: nextLayout, named: named, avoiding: other) }
        guard let index else { return nil }
        let id = plan.lanes[index].id
        reveal = SortReveal(id: 0, lane: id, token: reveal.token + 1)
        if focus { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.focusName = id } }
        return index
    }

    func cycleLayout(of lane: Int, by delta: Int = 1) { edit { $0.cycleLayout(of: lane, by: delta, in: layouts) } }

    func cycleNextLayout(by delta: Int = 1) {
        let i = layouts.firstIndex(of: nextLayout) ?? -1
        nextLayout = layouts[((i + delta) % layouts.count + layouts.count) % layouts.count]
    }

    func closeLane(_ id: UUID) {
        guard var p = plans[current], p.lanes.count > 1, let i = p.lanes.firstIndex(where: { $0.id == id }) else { return }
        let before = p, title = p.title(of: i)
        guard let n = p.closeLane(at: i) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        notice = SortNotice(text: n > 0 ? "Closing \(title). Its \(n) window\(n == 1 ? "" : "s") will close when you finish." : "Removed \(title).",
                            undo: (current, before))
    }

    func restore(_ id: CGWindowID) {
        let other = reserved()
        edit { $0.restore(id, avoiding: other) }
        show(id)
    }

    func reopen(_ group: UUID) {
        let other = reserved()
        edit { $0.reopen(group, avoiding: other) }
    }

    func removeLane(_ i: Int) {
        guard var p = plans[current], p.lanes.count > 1, p.lanes.indices.contains(i) else { return }
        let before = p, title = p.title(of: i)
        guard let r = p.removeLane(at: i) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        notice = SortNotice(text: r.moved > 0 ? "Removed \(title). Its \(r.moved) window\(r.moved == 1 ? "" : "s") moved to \(p.lanes[r.target].ws)."
                                              : "Removed \(title).", undo: (current, before))
    }

    func mergeLane(_ id: UUID, into target: UUID) {
        guard var p = plans[current], let i = p.lanes.firstIndex(where: { $0.id == id }),
              let j = p.lanes.firstIndex(where: { $0.id == target }) else { return }
        let before = p, title = p.title(of: i)
        guard let r = p.mergeLane(i, into: j) else { return }
        p.touched = true
        p.pending = true
        plans[current] = p
        changed()
        reveal = SortReveal(id: 0, lane: target, token: reveal.token + 1)
        notice = SortNotice(text: r.moved > 0 ? "Merged \(title) into \(p.title(of: r.target)). \(r.moved) window\(r.moved == 1 ? "" : "s") moved."
                                              : "Removed \(title).", undo: (current, before))
    }

    func moveLane(_ id: UUID, toSlot slot: Int) {
        guard let i = plan.lanes.firstIndex(where: { $0.id == id }) else { return }
        var at: Int?
        edit { at = $0.moveLane(i, toSlot: slot) }
        guard at != nil else { return }
        reveal = SortReveal(id: 0, lane: id, token: reveal.token + 1)
    }

    func undoRemove() {
        guard let u = notice?.undo else { return }
        var restored = u.plan
        for (i, lane) in restored.lanes.enumerated() {
            if let now = plans[u.display]?.lanes.first(where: { $0.id == lane.id }) { restored.lanes[i].name = now.name }
        }
        plans[u.display] = restored
        plans[u.display]?.touched = true
        plans[u.display]?.pending = true
        notice = nil
        changed()
    }

}
