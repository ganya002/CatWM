import AppKit

struct SortLane: Identifiable {
    let id = UUID()
    var ws: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}
