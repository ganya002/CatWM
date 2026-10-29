import CoreGraphics
import Foundation

struct TabInteraction {
    var minimizingTabs: Set<Int> = []
    let drag = TabDrag()
    var parkedTabs: Set<CGWindowID> = []
    var closedTabs: [CGWindowID: Date] = [:]
    var tabFollow: (previous: CGWindowID, at: Date)?
    var savedTabs: [SavedTabs] = []
    var savedTabsUntil = Date.distantPast
}
