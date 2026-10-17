import AppKit

extension SortPlan {
    @discardableResult
    mutating func addLane(layout: Layout, named: String? = nil, avoiding other: Set<String>) -> Int? {
        let free = available(avoiding: other)
        guard lanes.count < Self.maxLanes else { return nil }
        let name: String
        if let named {
            guard free.contains(named) else { return nil }
            name = named
        } else if let first = free.first {
            name = first
        } else {
            return nil
        }
        let at = lanes.firstIndex { Self.order(name, $0.ws) } ?? lanes.count
        lanes.insert(SortLane(ws: name, name: "", layout: layout, ids: []), at: at)
        return at
    }

    mutating func closeLane(at i: Int) -> Int? {
        guard lanes.count > 1, lanes.indices.contains(i) else { return nil }
        let lane = lanes.remove(at: i)
        guard !lane.ids.isEmpty else { return 0 }
        closedLanes.append(SortClosedLane(ws: lane.ws, name: lane.name, layout: lane.layout, ids: lane.ids))
        close += lane.ids
        return lane.ids.count
    }

    mutating func restore(_ id: CGWindowID, avoiding other: Set<String>) {
        guard isClosing(id) else { return }
        if let g = closedLanes.first(where: { $0.ids.contains(id) }) { return reopen(g.id, avoiding: other) }
        if let o = origin[id], let l = lanes.firstIndex(where: { $0.ws == o.ws }) {
            place(id, inLane: l, at: o.at)
        } else {
            place(id, inLane: activeLane)
        }
    }

    mutating func reopen(_ group: UUID, avoiding other: Set<String>) {
        guard let g = closedLanes.first(where: { $0.id == group }) else { return }
        let free = available(avoiding: other)
        guard lanes.count < Self.maxLanes, let ws = free.contains(g.ws) ? g.ws : free.first else {
            for id in g.ids { place(id, inLane: activeLane) }
            return
        }
        close.removeAll { g.ids.contains($0) }
        for id in g.ids { origin[id] = nil }
        closedLanes.removeAll { $0.id == group }
        lanes.insert(SortLane(ws: ws, name: g.name, layout: g.layout, ids: g.ids), at: lanes.firstIndex { Self.order(ws, $0.ws) } ?? lanes.count)
    }

    mutating func renumberLane(_ i: Int, to ws: String) {
        guard lanes.indices.contains(i) else { return }
        let id = lanes[i].id, old = lanes[i].ws
        lanes.removeAll { $0.ws == ws && $0.id != id }
        guard let at = lanes.firstIndex(where: { $0.id == id }) else { return }
        lanes[at].ws = ws
        lanes.sort { Self.order($0.ws, $1.ws) }
        for (k, o) in origin where o.ws == old { origin[k] = (ws, o.at) }
    }

    mutating func removeLane(at i: Int) -> (target: Int, moved: Int)? {
        guard lanes.count > 1, lanes.indices.contains(i) else { return nil }
        let moved = lanes[i].ids
        let target = i > 0 ? i - 1 : 1
        lanes[target].ids += moved
        lanes.remove(at: i)
        return (i > 0 ? i - 1 : 0, moved.count)
    }

    mutating func mergeLane(_ i: Int, into j: Int) -> (target: Int, moved: Int)? {
        guard i != j, lanes.indices.contains(i), lanes.indices.contains(j) else { return nil }
        let moved = lanes[i].ids
        lanes[j].ids += moved
        lanes.remove(at: i)
        return (j > i ? j - 1 : j, moved.count)
    }

    mutating func moveLane(_ i: Int, toSlot slot: Int) -> Int? {
        guard lanes.indices.contains(i), (0...lanes.count).contains(slot), slot != i, slot != i + 1 else { return nil }
        let names = lanes.map(\.ws)
        let lane = lanes.remove(at: i)
        let at = slot > i ? slot - 1 : slot
        lanes.insert(lane, at: at)
        for k in lanes.indices { lanes[k].ws = names[k] }
        return at
    }

    mutating func cycleLayout(of lane: Int, by delta: Int, in layouts: [Layout]) {
        guard lanes.indices.contains(lane), !layouts.isEmpty else { return }
        let i = layouts.firstIndex(of: lanes[lane].layout) ?? -1
        lanes[lane].layout = layouts[((i + delta) % layouts.count + layouts.count) % layouts.count]
    }

    mutating func reorder(_ id: CGWindowID, by delta: Int) {
        if let i = close.firstIndex(of: id) {
            let j = i + delta
            if close.indices.contains(j) { close.swapAt(i, j) }
        } else if let l = lane(of: id), let i = lanes[l].ids.firstIndex(of: id) {
            let j = i + delta
            if lanes[l].ids.indices.contains(j) { lanes[l].ids.swapAt(i, j) }
        }
    }

    mutating func moveToTop(_ id: CGWindowID) {
        guard let l = lane(of: id) else { return }
        place(id, inLane: l, at: 0)
    }
}
