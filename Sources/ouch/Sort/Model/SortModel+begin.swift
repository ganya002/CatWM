import AppKit
import SwiftUI

extension SortModel {
    func begin(displays: [SortDisplay], start: String, config: Config) {
        self.displays = displays
        layouts = config.layouts.isEmpty ? [.tall] : config.layouts
        strategy = config.sortStrategy
        nextLayout = layouts.contains(.tall) ? .tall : layouts[0]
        plans = [:]
        hover = nil; selected = nil; notice = nil; drag = nil; columnDrag = nil; over = nil; columnSlot = nil; focusName = nil
        running = true
        binds = [:]
        var modes: [String] = []
        for b in config.bindings where !b.submap.isEmpty && !modes.contains(b.submap) { modes.append(b.submap) }
        let mode = modes.first { $0.lowercased() == "window" } ?? modes.first ?? ""
        for b in config.bindings where b.submap == mode { binds[Self.key(b.keyCode, b.mods)] = b }
        use(start)
    }

    static func key(_ code: UInt16, _ mods: CGEventFlags) -> UInt64 {
        mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).rawValue | UInt64(code)
    }

    func end() {
        running = false
        edgeTimer?.invalidate()
        edgeTimer = nil
        if let o = scrollObserver { NotificationCenter.default.removeObserver(o) }
        scrollObserver = nil
        scroller = nil
        drag = nil; columnDrag = nil; over = nil; columnSlot = nil; hover = nil
    }

    func display(_ uuid: String) -> SortDisplay? { displays.first { $0.id == uuid } }

    func count(of uuid: String) -> Int { plans[uuid]?.items.count ?? display(uuid)?.items.count ?? 0 }

    func ensurePlan(_ uuid: String, grouped: Bool) {
        guard plans[uuid] == nil, let d = display(uuid) else { return }
        if grouped && !d.isSorted {
            var p = SortPlan.grouped(d, by: strategy, layouts: layouts, avoiding: reserved(excluding: uuid))
            p.touched = true
            p.pending = true
            plans[uuid] = p
        } else {
            plans[uuid] = .current(of: d)
        }
    }

    func reserved(excluding uuid: String? = nil) -> Set<String> {
        Set(plans.filter { $0.key != (uuid ?? current) }.values.flatMap { $0.lanes.map(\.ws) })
    }

    func use(_ uuid: String) {
        guard display(uuid) != nil else { return }
        current = uuid
        ensurePlan(uuid, grouped: true)
        selected = nil; hover = nil; notice = nil
        scrollToStart()
        if plans[uuid]?.pending == true { changed() }
    }

    func cycleDisplay(_ delta: Int) {
        guard displays.count > 1, let i = displays.firstIndex(where: { $0.id == current }) else { return }
        use(displays[((i + delta) % displays.count + displays.count) % displays.count].id)
    }

    func edit(keepNotice: Bool = false, _ change: (inout SortPlan) -> Void) {
        guard var p = plans[current] else { return }
        change(&p)
        p.touched = true
        p.pending = true
        plans[current] = p
        if !keepNotice { notice = nil }
        changed()
    }

    func pick(_ s: SortStrategy) {
        strategy = s
        let other = reserved()
        edit { $0.sort(by: s, layouts: layouts, avoiding: other) }
        selected = nil
        scrollToStart()
    }

    func closeDuplicates() { edit { $0.closeDuplicates() } }

    func rename(_ lane: UUID, _ name: String) {
        edit(keepNotice: true) { p in
            if let i = p.lanes.firstIndex(where: { $0.id == lane }) { p.lanes[i].name = name }
        }
    }

    func renumber(_ lane: UUID, to text: String) {
        let p = plan
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let i = p.lanes.firstIndex(where: { $0.id == lane }), !t.isEmpty, t != p.lanes[i].ws else { return }
        guard t.allSatisfy(\.isASCII), let n = Int(t), (1...SortPlan.maxLanes).contains(n) else {
            notice = SortNotice(text: "Workspace numbers run from 1 to \(SortPlan.maxLanes).", undo: nil)
            return
        }
        let ws = String(n)
        if p.taken.contains(ws) || reserved().contains(ws) {
            notice = SortNotice(text: "Workspace \(ws) is on another display.", undo: nil)
        } else if let held = p.lanes.first(where: { $0.ws == ws }), !held.ids.isEmpty || !held.name.trimmingCharacters(in: .whitespaces).isEmpty {
            notice = SortNotice(text: "Workspace \(ws) is in use. Move its windows away first.", undo: nil)
        } else {
            edit { $0.renumberLane(i, to: ws) }
            reveal = SortReveal(id: 0, lane: lane, token: reveal.token + 1)
        }
    }

    func pendingApplies() -> [SortApply] {
        let others = displays.map(\.id).filter { $0 != current }.compactMap { plans[$0] }.filter(\.pending)
        return (others + [plans[current]].compactMap { $0 }.filter(\.pending)).map(\.applied)
    }

    func markApplied() {
        for (k, p) in plans where p.pending {
            plans[k]?.pending = false
            plans[k]?.claimed.formUnion(p.lanes.map(\.ws))
        }
    }

    func result() -> (changed: Bool, closing: [CGWindowID], workspaces: Int) {
        let edited = plans.values.filter(\.touched)
        return (!edited.isEmpty, edited.flatMap(\.close), edited.reduce(0) { $0 + $1.lanes.filter { !$0.ids.isEmpty }.count })
    }

}
