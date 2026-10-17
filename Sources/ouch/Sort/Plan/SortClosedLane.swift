import AppKit

struct SortClosedLane: Identifiable {
    let id = UUID()
    var ws: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}
