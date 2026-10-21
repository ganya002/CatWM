import AppKit
import SwiftUI

extension SortModel {
    func prune(alive: Set<CGWindowID>) {
        for key in plans.keys {
            guard var displayPlan = plans[key] else { continue }
            let gone = displayPlan.items.keys.filter { !alive.contains($0) }
            guard !gone.isEmpty else { continue }
            for id in gone {
                displayPlan.detach(id)
                displayPlan.items[id] = nil
            }
            plans[key] = displayPlan
            if let selected, gone.contains(selected) { self.selected = nil }
            if let hover, gone.contains(hover) { self.hover = nil }
        }
    }

    func target() -> CGWindowID? { hover ?? selected }

    func place(_ id: CGWindowID, inLane i: Int, at index: Int? = nil) {
        if let item = unplacedFullscreen(id) {
            edit { $0.adopt(item, inLane: i, at: index) }
        } else {
            edit { $0.place(id, inLane: i, at: index) }
        }
        show(id)
    }

    func unplacedFullscreen(_ id: CGWindowID) -> SortItem? {
        plan.items[id] == nil ? currentDisplay?.fullscreen.first { $0.id == id } : nil
    }

    func fullscreenMoves() -> [CGWindowID: String] {
        var out: [CGWindowID: String] = [:]
        for display in displays {
            guard let displayPlan = plans[display.id] else { continue }
            out.merge(displayPlan.moves(of: Set(display.fullscreen.map(\.id)))) { first, _ in first }
        }
        return out
    }

    func markClosing(_ id: CGWindowID) {
        guard unplacedFullscreen(id) == nil else { return }
        edit { $0.markClosing(id) }
        show(id)
    }

    func toggleClose(_ id: CGWindowID) {
        if plan.isClosing(id) {
            restore(id)
        } else {
            markClosing(id)
        }
    }

    func send(_ id: CGWindowID, toWorkspace workspace: String) {
        if let i = plan.lanes.firstIndex(where: { $0.workspace == workspace }) {
            place(id, inLane: i)
        } else if let new = addLane(focus: false, named: workspace) {
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
        guard var displayPlan = plans[current],
              displayPlan.lanes.count > 1,
              let i = displayPlan.lanes.firstIndex(where: { $0.id == id }) else { return }
        let before = displayPlan, title = displayPlan.title(of: i)
        guard let count = displayPlan.closeLane(at: i) else { return }
        displayPlan.touched = true
        displayPlan.pending = true
        plans[current] = displayPlan
        changed()
        let text = count > 0
            ? "Closing \(title). Its \(count) window\(count == 1 ? "" : "s") will close when you finish."
            : "Removed \(title)."
        notice = SortNotice(text: text, undo: (current, before))
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
        guard var displayPlan = plans[current], displayPlan.lanes.count > 1,
              displayPlan.lanes.indices.contains(i) else { return }
        let before = displayPlan, title = displayPlan.title(of: i)
        guard let result = displayPlan.removeLane(at: i) else { return }
        displayPlan.touched = true
        displayPlan.pending = true
        plans[current] = displayPlan
        changed()
        let moved = result.moved
        let text = moved > 0
            ? "Removed \(title). Its \(moved) window\(moved == 1 ? "" : "s") moved to "
                + "\(displayPlan.lanes[result.target].number)."
            : "Removed \(title)."
        notice = SortNotice(text: text, undo: (current, before))
    }

    func mergeLane(_ id: UUID, into target: UUID) {
        guard var displayPlan = plans[current], let i = displayPlan.lanes.firstIndex(where: { $0.id == id }),
              let j = displayPlan.lanes.firstIndex(where: { $0.id == target }) else { return }
        let before = displayPlan, title = displayPlan.title(of: i)
        guard let result = displayPlan.mergeLane(i, into: j) else { return }
        displayPlan.touched = true
        displayPlan.pending = true
        plans[current] = displayPlan
        changed()
        reveal = SortReveal(id: 0, lane: target, token: reveal.token + 1)
        let moved = result.moved
        let text = moved > 0
            ? "Merged \(title) into \(displayPlan.title(of: result.target)). "
                + "\(moved) window\(moved == 1 ? "" : "s") moved."
            : "Removed \(title)."
        notice = SortNotice(text: text, undo: (current, before))
    }

    func moveLane(_ id: UUID, toSlot slot: Int) {
        guard let i = plan.lanes.firstIndex(where: { $0.id == id }) else { return }
        var moved: Int?
        edit { moved = $0.moveLane(i, toSlot: slot) }
        guard moved != nil else { return }
        reveal = SortReveal(id: 0, lane: id, token: reveal.token + 1)
    }

    func undoRemove() {
        guard let undo = notice?.undo else { return }
        var restored = undo.plan
        for (i, lane) in restored.lanes.enumerated() {
            if let now = plans[undo.display]?.lanes.first(where: { $0.id == lane.id }) {
                restored.lanes[i].name = now.name
            }
        }
        plans[undo.display] = restored
        plans[undo.display]?.touched = true
        plans[undo.display]?.pending = true
        notice = nil
        changed()
    }
}
