import AppKit

struct SortApply {
    let display: String
    var lanes: [SortApplyLane]
    var close: [CGWindowID]
    var dropped: [String]
    var tabs: [[CGWindowID]] = []
}
