import AppKit

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
                            lanes: lanes, strategy: nil,
                            existing: display.workspaces.map(\.name), taken: display.taken, active: display.active)
        plan.perDisplay = display.perDisplay
        plan.tabs = display.tabs
        plan.keepTabsTogether()
        for workspace in display.workspaces { plan.geometry[workspace.name] = (workspace.ratio, workspace.mainCount) }
        return plan
    }

    static func grouped(_ display: SortDisplay, by strategy: SortStrategy, layouts: [Layout],
                        avoiding other: Set<String>) -> SortPlan {
        var plan = current(of: display)
        plan.sort(by: strategy, layouts: layouts, avoiding: other)
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

    func title(of lane: Int) -> String {
        let name = lanes[lane].name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Workspace \(lanes[lane].number)" : name
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

    mutating func sort(by sortStrategy: SortStrategy, layouts: [Layout], avoiding other: Set<String>) {
        strategy = sortStrategy
        let dupes = duplicatesClosed ? Set(duplicates) : []
        let live = items.values.filter { !dupes.contains($0.id) }.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }
        var groups = Self.groups(of: live, by: sortStrategy).filter { !$0.items.isEmpty }
        if groups.isEmpty { groups = [SortGroup(name: "", items: [])] }
        lanes = []
        let pool = available(avoiding: other)
        let cap = max(1, min(Self.maxLanes, pool.count))
        while groups.count > cap {
            let last = groups.removeLast()
            groups[groups.count - 1].items += last.items
        }
        let names = Array(pool.prefix(groups.count)).sorted(by: Self.order)
        lanes = groups.enumerated().map { i, group in
            SortLane(workspace: i < names.count ? names[i] : existing.first ?? key("1"), name: group.name,
                     layout: Self.fit(group.layout, group.items.count, layouts), ids: group.items.map(\.id))
        }
        closedLanes = []
        origin = [:]
        close = items.values
            .filter { dupes.contains($0.id) }
            .sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }
            .map(\.id)
        keepTabsTogether()
    }

    private static func groups(of live: [SortItem], by sortStrategy: SortStrategy) -> [SortGroup] {
        switch sortStrategy {
        case .task:
            return SortCategory.all.map { category in
                SortGroup(name: category.rawValue, items: live.filter { SortCategory.of($0.bundleID) == category })
            }
        case .app:
            var count: [String: Int] = [:]
            for item in live { count[item.app, default: 0] += 1 }
            let ranked = count.keys.sorted { lhs, rhs in
                count[lhs, default: 0] != count[rhs, default: 0]
                    ? count[lhs, default: 0] > count[rhs, default: 0]
                    : (live.first { $0.app == lhs }?.recency ?? 0) < (live.first { $0.app == rhs }?.recency ?? 0)
            }
            let own = Array(ranked.prefix(4))
            var groups = own.map { app in SortGroup(name: app, items: live.filter { $0.app == app }) }
            let rest = live.filter { !own.contains($0.app) }
            if !rest.isEmpty { groups.append(SortGroup(name: "Everything else", items: rest)) }
            return groups
        case .focus:
            return [SortGroup(name: "Now", items: Array(live.prefix(3))),
                    SortGroup(name: "Later", items: Array(live.dropFirst(3)), layout: .fullscreen)]
        case .none:
            return [SortGroup(name: "", items: live)]
        }
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
        for i in closedLanes.indices { closedLanes[i].ids.removeAll { $0 == id } }
        closedLanes.removeAll { $0.ids.isEmpty }
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

private struct SortGroup {
    var name: String
    var items: [SortItem]
    var layout: Layout?
}
