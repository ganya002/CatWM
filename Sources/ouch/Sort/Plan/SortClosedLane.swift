import AppKit

struct SortClosedLane: Identifiable {
    let id = UUID()
    var workspace: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}
