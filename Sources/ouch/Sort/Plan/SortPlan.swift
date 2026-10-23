import AppKit

struct SortPlan {
    static let maxLanes = 10

    let display: String
    var items: [CGWindowID: SortItem]
    var lanes: [SortLane]
    var close: [CGWindowID] = []
    var closedLanes: [SortClosedLane] = []
    var origin: [CGWindowID: (workspace: String, at: Int)] = [:]
    var strategy: SortStrategy?
    var duplicatesClosed = false
    var touched = false
    var pending = false
    let existing: [String]
    var claimed: Set<String> = []
    let taken: Set<String>
    var active: String?
    var perDisplay = false
    var geometry: [String: (ratio: CGFloat, mainCount: Int)] = [:]
    var tabs: [[CGWindowID]] = []

    func key(_ number: String) -> String { WorkspaceKey.make(number, on: display, perDisplay: perDisplay) }

    var activeLane: Int { lanes.firstIndex { $0.workspace == active } ?? 0 }

    var duplicates: [CGWindowID] {
        var groups: [String: [SortItem]] = [:]
        for item in items.values where !item.title.isEmpty && item.title != "Untitled" {
            groups["\(item.bundleID ?? item.app)\n\(item.title)", default: []].append(item)
        }
        return groups.values.flatMap { group in
            group.sorted { ($0.recency, $0.id) < ($1.recency, $1.id) }.dropFirst().map(\.id)
        }.sorted()
    }

    var duplicateText: String? {
        let open = duplicates.filter { !close.contains($0) }
        guard !open.isEmpty else { return nil }
        let apps = Set(open.compactMap { items[$0]?.app })
        let app = apps.count == 1 ? apps.first.map { $0 + " " } ?? "" : ""
        return "Close \(open.count) duplicate \(app)window\(open.count == 1 ? "" : "s")"
    }

    var allIDs: [CGWindowID] { lanes.flatMap(\.ids) + close }
}
