import AppKit

extension SortPlan {
    static func current(of d: SortDisplay) -> SortPlan {
        var lanes = d.workspaces.map { SortLane(ws: $0.name, name: $0.label, layout: $0.layout, ids: $0.ids) }
        if lanes.isEmpty { lanes = [SortLane(ws: "1", name: "", layout: .tall, ids: [])] }
        var plan = SortPlan(display: d.id, items: Dictionary(d.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
                            lanes: lanes, strategy: nil,
                            existing: d.workspaces.map(\.name), taken: d.taken, active: d.active)
        for w in d.workspaces { plan.geometry[w.name] = (w.ratio, w.mainCount) }
        return plan
    }

    static func grouped(_ d: SortDisplay, by strategy: SortStrategy, layouts: [Layout], avoiding other: Set<String>) -> SortPlan {
        var plan = current(of: d)
        plan.sort(by: strategy, layouts: layouts, avoiding: other)
        return plan
    }

    static func order(_ a: String, _ b: String) -> Bool {
        switch (Int(a), Int(b)) {
        case let (x?, y?): return x < y
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a < b
        }
    }

    func available(avoiding other: Set<String>) -> [String] {
        let used = Set(lanes.map(\.ws))
        var out: [String] = []
        for n in existing + (1...10).map(String.init) where !out.contains(n) && !used.contains(n) && !taken.contains(n) && !other.contains(n) {
            out.append(n)
        }
        return out
    }

    func canAdd(avoiding other: Set<String>) -> Bool { lanes.count < Self.maxLanes && !available(avoiding: other).isEmpty }

    func title(of lane: Int) -> String {
        let n = lanes[lane].name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Workspace \(lanes[lane].ws)" : n
    }

    static func layout(forCount n: Int, in layouts: [Layout]) -> Layout {
        let want: Layout = n <= 1 ? .fullscreen : n == 2 ? .column : n == 3 ? .tall : n == 4 ? .bsp : .tall
        return layouts.contains(want) ? want : layouts.first ?? .tall
    }

    mutating func sort(by s: SortStrategy, layouts: [Layout], avoiding other: Set<String>) {
        strategy = s
        let dupes = duplicatesClosed ? Set(duplicates) : []
        let live = items.values.filter { !dupes.contains($0.id) }.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }
        var groups: [(name: String, items: [SortItem], layout: Layout?)]
        switch s {
        case .task:
            groups = SortCategory.all.map { c in (c.rawValue, live.filter { SortCategory.of($0.bundleID) == c }, nil) }
        case .app:
            var count: [String: Int] = [:]
            for i in live { count[i.app, default: 0] += 1 }
            let ranked = count.keys.sorted { a, b in
                count[a]! != count[b]! ? count[a]! > count[b]!
                    : (live.first { $0.app == a }?.recency ?? 0) < (live.first { $0.app == b }?.recency ?? 0)
            }
            let own = Array(ranked.prefix(4))
            groups = own.map { a in (a, live.filter { $0.app == a }, nil) }
            let rest = live.filter { !own.contains($0.app) }
            if !rest.isEmpty { groups.append(("Everything else", rest, nil)) }
        case .focus:
            groups = [("Now", Array(live.prefix(3)), nil), ("Later", Array(live.dropFirst(3)), .fullscreen)]
        case .none:
            groups = [("", live, nil)]
        }
        groups = groups.filter { !$0.items.isEmpty }
        if groups.isEmpty { groups = [("", [], nil)] }
        lanes = []
        let pool = available(avoiding: other)
        let cap = max(1, min(Self.maxLanes, pool.count))
        while groups.count > cap {
            let last = groups.removeLast()
            groups[groups.count - 1].items += last.items
        }
        let names = Array(pool.prefix(groups.count)).sorted(by: Self.order)
        lanes = groups.enumerated().map { i, g in
            SortLane(ws: i < names.count ? names[i] : existing.first ?? "1", name: g.name,
                     layout: Self.fit(g.layout, g.items.count, layouts), ids: g.items.map(\.id))
        }
        closedLanes = []
        origin = [:]
        close = items.values.filter { dupes.contains($0.id) }.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }.map(\.id)
    }

    static func fit(_ forced: Layout?, _ n: Int, _ layouts: [Layout]) -> Layout {
        if let forced { return layouts.contains(forced) ? forced : layouts.first ?? .tall }
        return layout(forCount: n, in: layouts)
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
        let at = min(index ?? lanes[i].ids.count, lanes[i].ids.count)
        lanes[i].ids.insert(id, at: at)
    }

    mutating func markClosing(_ id: CGWindowID) {
        guard !isClosing(id) else { return }
        let from = lane(of: id).flatMap { l in lanes[l].ids.firstIndex(of: id).map { (lanes[l].ws, $0) } }
        detach(id)
        close.append(id)
        if let from { origin[id] = from }
    }
}
