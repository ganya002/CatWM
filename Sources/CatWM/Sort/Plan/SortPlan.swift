import AppKit
import CatWMKit

struct SortPlan {
    static let maxLanes = 10

    let display: String
    var items: [CGWindowID: SortItem]
    var lanes: [SortLane]
    var close: [CGWindowID] = []
    var closedLanes: [SortClosedLane] = []
    var origin: [CGWindowID: (workspace: String, at: Int)] = [:]
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

struct SortApply {
    let display: String
    var lanes: [SortApplyLane]
    var close: [CGWindowID]
    var dropped: [String]
    var tabs: [[CGWindowID]] = []
}

struct SortApplyLane {
    let name: String
    let label: String
    let layout: Layout
    let ids: [CGWindowID]
}

struct SortClosedLane: Identifiable {
    let id = UUID()
    var workspace: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]

    var number: String { WorkspaceKey.number(workspace) }
}

struct SortDisplay: Identifiable {
    let id: String
    let name: String
    let short: String
    let isLaptop: Bool
    let aspect: CGFloat
    let screen: NSScreen
    let items: [SortItem]
    let fullscreen: [SortItem]
    let workspaces: [SortWorkspace]
    let active: String?
    let taken: Set<String>
    var perDisplay = false
    var tabs: [[CGWindowID]] = []
}

struct SortItem: Identifiable {
    let id: CGWindowID
    let title: String
    let app: String
    let bundleID: String?
    let icon: NSImage?
    let recency: Int
}

struct SortLane: Identifiable {
    let id = UUID()
    var workspace: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]

    var number: String { WorkspaceKey.number(workspace) }
}

struct SortWorkspace {
    let name: String
    let label: String
    let layout: Layout
    let ratio: CGFloat
    let mainCount: Int
    let ids: [CGWindowID]
}

extension SortPlan {
    var applied: SortApply {
        SortApply(display: display,
                  lanes: lanes.map {
                      SortApplyLane(name: $0.workspace, label: $0.name.trimmingCharacters(in: .whitespaces),
                                    layout: $0.layout, ids: $0.ids)
                  },
                  close: close, dropped: Array(claimed.union(existing)), tabs: tabs)
    }
}
