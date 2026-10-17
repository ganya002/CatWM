import AppKit

struct SortPlan {

    static let maxLanes = 10

    let display: String
    var items: [CGWindowID: SortItem]
    var lanes: [SortLane]
    var close: [CGWindowID] = []
    var closedLanes: [SortClosedLane] = []
    var origin: [CGWindowID: (ws: String, at: Int)] = [:]
    var strategy: SortStrategy?
    var duplicatesClosed = false
    var touched = false
    var pending = false
    let existing: [String]
    var claimed: Set<String> = []
    let taken: Set<String>
    let active: String?
    var geometry: [String: (ratio: CGFloat, mainCount: Int)] = [:]

    var activeLane: Int { lanes.firstIndex { $0.ws == active } ?? 0 }

    var duplicates: [CGWindowID] {
        var groups: [String: [SortItem]] = [:]
        for i in items.values where !i.title.isEmpty && i.title != "Untitled" { groups["\(i.bundleID ?? i.app)\n\(i.title)", default: []].append(i) }
        return groups.values.flatMap { g in g.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }.dropFirst().map(\.id) }.sorted()
    }

    var duplicateText: String? {
        let d = duplicates.filter { !close.contains($0) }
        guard !d.isEmpty else { return nil }
        let apps = Set(d.compactMap { items[$0]?.app })
        return "Close \(d.count) duplicate \(apps.count == 1 ? apps.first! + " " : "")window\(d.count == 1 ? "" : "s")"
    }

    var allIDs: [CGWindowID] { lanes.flatMap(\.ids) + close }

}
