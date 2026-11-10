import AppKit
import CatWMKit
import SwiftUI

extension SortModel {
    func begin(displays: [SortDisplay], start: String, config: Config) {
        self.displays = displays
        layouts = config.layouts.isEmpty ? [.tall] : config.layouts
        nextLayout = layouts.contains(.tall) ? .tall : layouts[0]
        plans = [:]
        hover = nil
        selected = nil
        notice = nil
        drag = nil
        columnDrag = nil
        over = nil
        columnSlot = nil
        focusName = nil
        running = true
        binds = [:]
        var modes: [String] = []
        for bind in config.bindings where !bind.submap.isEmpty && !modes.contains(bind.submap) {
            modes.append(bind.submap)
        }
        let mode = modes.first { $0.lowercased() == "window" } ?? modes.first ?? ""
        for bind in config.bindings where bind.submap == mode { binds[Self.key(bind.keyCode, bind.mods)] = bind }
        use(start)
    }

    static func key(_ code: UInt16, _ mods: CGEventFlags) -> UInt64 {
        mods.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).rawValue | UInt64(code)
    }

    func end() {
        running = false
        edgeTimer?.invalidate()
        edgeTimer = nil
        if let observer = scrollObserver { NotificationCenter.default.removeObserver(observer) }
        scrollObserver = nil
        scroller = nil
        drag = nil; columnDrag = nil; over = nil; columnSlot = nil; hover = nil
    }

    func display(_ uuid: String) -> SortDisplay? { displays.first { $0.id == uuid } }

    func count(of uuid: String) -> Int { plans[uuid]?.items.count ?? display(uuid)?.items.count ?? 0 }

    func ensurePlan(_ uuid: String) {
        guard plans[uuid] == nil, let shown = display(uuid) else { return }
        plans[uuid] = .current(of: shown)
    }

    func reserved(excluding uuid: String? = nil) -> Set<String> {
        Set(plans.filter { $0.key != (uuid ?? current) }.values.flatMap { $0.lanes.map(\.workspace) })
    }

    func use(_ uuid: String) {
        guard display(uuid) != nil else { return }
        current = uuid
        ensurePlan(uuid)
        selected = nil; hover = nil; notice = nil
        scrollToStart()
        if plans[uuid]?.pending == true { changed() }
    }

    func cycleDisplay(_ delta: Int) {
        guard displays.count > 1, let i = displays.firstIndex(where: { $0.id == current }) else { return }
        use(displays[((i + delta) % displays.count + displays.count) % displays.count].id)
    }

    func edit(keepNotice: Bool = false, _ change: (inout SortPlan) -> Void) {
        guard var displayPlan = plans[current] else { return }
        change(&displayPlan)
        displayPlan.keepTabsTogether()
        displayPlan.touched = true
        displayPlan.pending = true
        plans[current] = displayPlan
        if !keepNotice { notice = nil }
        changed()
    }

    func closeDuplicates() { edit { $0.closeDuplicates() } }

    func rename(_ lane: UUID, _ name: String) {
        edit(keepNotice: true) { displayPlan in
            if let i = displayPlan.lanes.firstIndex(where: { $0.id == lane }) { displayPlan.lanes[i].name = name }
        }
    }

    func renumber(_ lane: UUID, to text: String) {
        let snapshot = plan
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let i = snapshot.lanes.firstIndex(where: { $0.id == lane }),
              !trimmed.isEmpty,
              trimmed != snapshot.lanes[i].number else { return }
        guard trimmed.allSatisfy(\.isASCII), let number = Int(trimmed), (1...SortPlan.maxLanes).contains(number) else {
            notice = SortNotice(text: "Workspace numbers run from 1 to \(SortPlan.maxLanes).")
            return
        }
        let workspace = snapshot.key(String(number))
        guard workspace != snapshot.lanes[i].workspace else { return }
        if snapshot.perDisplay {
            notice = SortNotice(text: "Workspaces follow the order of your Desktops. Drag a column to reorder.")
        } else if snapshot.taken.contains(workspace) || reserved().contains(workspace) {
            notice = SortNotice(text: "Workspace \(number) is on another display.")
        } else if let held = snapshot.lanes.first(where: { $0.workspace == workspace }),
                  !held.ids.isEmpty || !held.name.trimmingCharacters(in: .whitespaces).isEmpty {
            notice = SortNotice(text: "Workspace \(number) is in use. Move its windows away first.")
        } else {
            edit { $0.renumberLane(i, to: workspace) }
            reveal = SortReveal(id: 0, lane: lane, token: reveal.token + 1)
        }
    }

    func pendingApplies() -> [SortApply] {
        let others = displays.map(\.id).filter { $0 != current }.compactMap { plans[$0] }.filter(\.pending)
        return (others + [plans[current]].compactMap(\.self).filter(\.pending)).map(\.applied)
    }

    func markApplied() {
        for (key, displayPlan) in plans where displayPlan.pending {
            plans[key]?.pending = false
            plans[key]?.claimed.formUnion(displayPlan.lanes.map(\.workspace))
        }
    }

    func result() -> SortResult {
        let edited = plans.values.filter(\.touched)
        return SortResult(changed: !edited.isEmpty, closing: edited.flatMap(\.close))
    }
}
