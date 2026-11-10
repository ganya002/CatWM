import CatWMKit
import CoreGraphics

extension SortPlan {
    func tabs(of id: CGWindowID) -> [CGWindowID] { tabs.first { $0.contains(id) } ?? [id] }

    func isTabbed(_ id: CGWindowID) -> Bool { tabs.contains { $0.contains(id) } }

    func isBackTab(_ id: CGWindowID, in ids: [CGWindowID]) -> Bool {
        isTabbed(id) && tabs(of: id).first(where: ids.contains) != id
    }

    func tiles(_ ids: [CGWindowID]) -> [CGWindowID] { ids.filter { !isBackTab($0, in: ids) } }

    func tabBlocks(_ ids: [CGWindowID]) -> [[CGWindowID]] {
        var blocks: [[CGWindowID]] = []
        for id in ids {
            if isTabbed(id), let lead = blocks.last?.first, tabs(of: id).contains(lead) {
                blocks[blocks.count - 1].append(id)
            } else {
                blocks.append([id])
            }
        }
        return blocks
    }

    func rowCount(_ lane: SortLane) -> Int { lane.ids.count + tabBlocks(lane.ids).filter { isTabbed($0[0]) }.count }

    func closeBlocks(_ ids: [CGWindowID]) -> [[CGWindowID]] {
        var blocks: [[CGWindowID]] = []
        for id in ids where !blocks.contains(where: { $0.contains(id) }) {
            blocks.append(isTabbed(id) ? tabs(of: id).filter(ids.contains) : [id])
        }
        return blocks
    }

    var closeRowCount: Int {
        let grouped = Set(closedLanes.flatMap(\.ids))
        let sections = closedLanes.map(\.ids) + [close.filter { !grouped.contains($0) }]
        return close.count + closedLanes.count + sections.flatMap(closeBlocks).filter { $0.count > 1 }.count
    }

    mutating func untab(_ id: CGWindowID) {
        for i in tabs.indices { tabs[i].removeAll { $0 == id } }
        tabs.removeAll(where: \.isEmpty)
    }

    mutating func joinTabs(_ id: CGWindowID, onto target: CGWindowID) {
        guard id != target, !tabs(of: target).contains(id), let home = lane(of: target) else { return }
        untab(id)
        if let group = tabs.firstIndex(where: { $0.contains(target) }) {
            tabs[group].append(id)
        } else {
            tabs.append([target, id])
        }
        let members = tabs(of: target)
        let last = lanes[home].ids.lastIndex(where: members.contains) ?? lanes[home].ids.count - 1
        place(id, inLane: home, at: last + 1)
    }

    mutating func placeTabs(_ id: CGWindowID, inLane i: Int) {
        let fromClose = isClosing(id)
        let members = tabs(of: id).filter { $0 == id || (fromClose ? isClosing($0) : lane(of: $0) != nil) }
        for member in members { place(member, inLane: i) }
    }

    mutating func keepTabsTogether() {
        for group in tabs {
            let placed = group.filter { lane(of: $0) != nil }
            guard placed.count > 1, let home = lane(of: placed[0]) else { continue }
            let start = lanes[home].ids.prefix { !placed.contains($0) }.count
            for i in lanes.indices { lanes[i].ids.removeAll(where: placed.contains) }
            lanes[home].ids.insert(contentsOf: placed, at: min(start, lanes[home].ids.count))
        }
    }
}
