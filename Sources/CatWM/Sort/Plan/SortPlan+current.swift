import AppKit
import CatWMKit

extension SortPlan {
    static func current(of display: SortDisplay) -> SortPlan {
        var lanes = display.workspaces.map {
            SortLane(workspace: $0.name, name: $0.label, layout: $0.layout, ids: $0.ids)
        }
        if lanes.isEmpty {
            let first = WorkspaceKey.make("1", on: display.id, perDisplay: display.perDisplay)
            lanes = [SortLane(workspace: first, name: "", layout: .tall, ids: [])]
        }
        let items = Dictionary(display.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var plan = SortPlan(display: display.id, items: items,
                            lanes: lanes,
                            existing: display.workspaces.map(\.name), taken: display.taken, active: display.active)
        plan.perDisplay = display.perDisplay
        plan.tabs = display.tabs
        plan.keepTabsTogether()
        for workspace in display.workspaces { plan.geometry[workspace.name] = (workspace.ratio, workspace.mainCount) }
        return plan
    }

    static func order(_ lhs: String, _ rhs: String) -> Bool {
        switch (Int(WorkspaceKey.number(lhs)), Int(WorkspaceKey.number(rhs))) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs < rhs
        }
    }

    func available(avoiding other: Set<String>) -> [String] {
        let used = Set(lanes.map(\.workspace))
        var out: [String] = []
        for name in existing + (1...10).map({ key(String($0)) })
        where !out.contains(name) && !used.contains(name) && !taken.contains(name) && !other.contains(name) {
            out.append(name)
        }
        return out
    }

    func canAdd(avoiding other: Set<String>) -> Bool {
        lanes.count < Self.maxLanes && !available(avoiding: other).isEmpty
    }

    static func layout(forCount count: Int, in layouts: [Layout]) -> Layout {
        let want: Layout
        switch count {
        case ...1: want = .fullscreen
        case 2: want = .column
        case 4: want = .bsp
        default: want = .tall
        }
        return layouts.contains(want) ? want : layouts.first ?? .tall
    }

    static func fit(_ forced: Layout?, _ count: Int, _ layouts: [Layout]) -> Layout {
        if let forced { return layouts.contains(forced) ? forced : layouts.first ?? .tall }
        return layout(forCount: count, in: layouts)
    }

    mutating func closeDuplicates() {
        duplicatesClosed = true
        duplicates.forEach { markClosing($0) }
    }

    func lane(of id: CGWindowID) -> Int? { lanes.firstIndex { $0.ids.contains(id) } }
    func isClosing(_ id: CGWindowID) -> Bool { close.contains(id) }
    mutating func detach(_ id: CGWindowID) {
        for i in lanes.indices { lanes[i].ids.removeAll { $0 == id } }
        close.removeAll { $0 == id }
        origin[id] = nil
        closedLanes.removeAll { $0.ids == [id] }
        for i in closedLanes.indices { closedLanes[i].ids.removeAll { $0 == id } }
    }

    mutating func place(_ id: CGWindowID, inLane i: Int, at index: Int? = nil) {
        guard lanes.indices.contains(i) else { return }
        detach(id)
        let position = min(index ?? lanes[i].ids.count, lanes[i].ids.count)
        lanes[i].ids.insert(id, at: position)
    }

    mutating func adopt(_ item: SortItem, inLane i: Int, at index: Int? = nil) {
        guard lanes.indices.contains(i) else { return }
        items[item.id] = item
        place(item.id, inLane: i, at: index)
    }

    func moves(of ids: Set<CGWindowID>) -> [CGWindowID: String] {
        var out: [CGWindowID: String] = [:]
        for lane in lanes { for id in lane.ids where ids.contains(id) { out[id] = lane.workspace } }
        return out
    }

    mutating func markClosing(_ id: CGWindowID) {
        guard !isClosing(id) else { return }
        let from = lane(of: id).flatMap { laneIndex in
            lanes[laneIndex].ids.firstIndex(of: id).map { (lanes[laneIndex].workspace, $0) }
        }
        detach(id)
        close.append(id)
        if let from { origin[id] = from }
    }
}
