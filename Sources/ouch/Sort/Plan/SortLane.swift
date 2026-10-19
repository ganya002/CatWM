import AppKit

struct SortLane: Identifiable {
    let id = UUID()
    var workspace: String
    var name: String
    var layout: Layout
    var ids: [CGWindowID]
}
