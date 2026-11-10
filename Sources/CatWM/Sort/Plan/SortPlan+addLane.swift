import AppKit
import CatWMKit

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
        let position = lanes.firstIndex { Self.order(name, $0.workspace) } ?? lanes.count
        lanes.insert(SortLane(workspace: name, name: "", layout: layout, ids: []), at: position)
        return position
    }

    @discardableResult
    mutating func closeLane(at i: Int) -> Int? {
        guard lanes.count > 1, lanes.indices.contains(i) else { return nil }
        let lane = lanes.remove(at: i)
        closedLanes.append(SortClosedLane(workspace: lane.workspace, name: lane.name,
                                          layout: lane.layout, ids: lane.ids))
        close += lane.ids
        return lane.ids.count
    }

    mutating func restore(_ id: CGWindowID, avoiding other: Set<String>) {
        guard isClosing(id) else { return }
        if let group = closedLanes.first(where: { $0.ids.contains(id) }) { return reopen(group.id, avoiding: other) }
        let grouped = Set(closedLanes.flatMap(\.ids))
        let members = tabs(of: id).filter { isClosing($0) && !grouped.contains($0) }
        for member in members {
            if let from = origin[member],
               let laneIndex = lanes.firstIndex(where: { $0.workspace == from.workspace }) {
                place(member, inLane: laneIndex, at: from.at)
            } else {
                place(member, inLane: activeLane)
            }
        }
        keepTabsTogether()
    }

    mutating func reopen(_ group: UUID, avoiding other: Set<String>) {
        guard let closed = closedLanes.first(where: { $0.id == group }) else { return }
        let free = available(avoiding: other)
        guard lanes.count < Self.maxLanes,
              let workspace = free.contains(closed.workspace) ? closed.workspace : free.first else {
            for id in closed.ids { place(id, inLane: activeLane) }
            return
        }
        close.removeAll { closed.ids.contains($0) }
        for id in closed.ids { origin[id] = nil }
        closedLanes.removeAll { $0.id == group }
        lanes.insert(SortLane(workspace: workspace, name: closed.name, layout: closed.layout, ids: closed.ids),
                     at: lanes.firstIndex { Self.order(workspace, $0.workspace) } ?? lanes.count)
    }

    mutating func followDesktopOrder() {
        guard perDisplay else { return }
        var renamed: [String: String] = [:]
        for i in lanes.indices {
            renamed[lanes[i].workspace] = key(String(i + 1))
            lanes[i].workspace = key(String(i + 1))
        }
        guard renamed.contains(where: { $0.key != $0.value }) else { return }
        geometry = Dictionary(geometry.map { (renamed[$0.key] ?? $0.key, $0.value) },
                              uniquingKeysWith: { first, _ in first })
        origin = origin.mapValues { (renamed[$0.workspace] ?? $0.workspace, $0.at) }
        active = active.map { renamed[$0] ?? $0 }
    }

    mutating func renumberLane(_ i: Int, to workspace: String) {
        guard lanes.indices.contains(i) else { return }
        let id = lanes[i].id, old = lanes[i].workspace
        lanes.removeAll { $0.workspace == workspace && $0.id != id }
        guard let position = lanes.firstIndex(where: { $0.id == id }) else { return }
        lanes[position].workspace = workspace
        lanes.sort { Self.order($0.workspace, $1.workspace) }
        for (key, from) in origin where from.workspace == old { origin[key] = (workspace, from.at) }
    }

    @discardableResult
    mutating func mergeLane(_ i: Int, into j: Int) -> (target: Int, moved: Int)? {
        guard i != j, lanes.indices.contains(i), lanes.indices.contains(j) else { return nil }
        let moved = lanes[i].ids
        lanes[j].ids += moved
        lanes.remove(at: i)
        return (j > i ? j - 1 : j, moved.count)
    }

    mutating func moveLane(_ i: Int, toSlot slot: Int) -> Int? {
        guard lanes.indices.contains(i), (0...lanes.count).contains(slot), slot != i, slot != i + 1 else { return nil }
        let names = lanes.map(\.workspace)
        let lane = lanes.remove(at: i)
        let position = slot > i ? slot - 1 : slot
        lanes.insert(lane, at: position)
        let renamed = Dictionary(uniqueKeysWithValues: lanes.indices.map { (lanes[$0].workspace, names[$0]) })
        for index in lanes.indices { lanes[index].workspace = names[index] }
        origin = origin.mapValues { (renamed[$0.workspace] ?? $0.workspace, $0.at) }
        return position
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
        } else if let laneIndex = lane(of: id) {
            var blocks = tabBlocks(lanes[laneIndex].ids)
            guard let i = blocks.firstIndex(where: { $0.contains(id) }),
                  blocks.indices.contains(i + delta) else { return }
            blocks.swapAt(i, i + delta)
            lanes[laneIndex].ids = blocks.flatMap(\.self)
        }
    }

    mutating func moveToTop(_ id: CGWindowID) {
        guard let laneIndex = lane(of: id) else { return }
        place(id, inLane: laneIndex, at: 0)
    }
}
