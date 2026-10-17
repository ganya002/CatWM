import AppKit

struct SortApply {
    let display: String
    var lanes: [(name: String, label: String, layout: Layout, ids: [CGWindowID])]
    var close: [CGWindowID]
    var dropped: [String]
}
