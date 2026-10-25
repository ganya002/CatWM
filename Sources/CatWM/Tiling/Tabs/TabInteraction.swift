import CoreGraphics
import Foundation

struct TabInteraction {
    var minimizingTabs: Set<Int> = []
    var tabHover: (host: CGWindowID, settled: Bool)?
    var tabHoverWork: DispatchWorkItem?
    var draggedTab: CGWindowID?
    var tabDropCancelled = false
    var parkedTabs: Set<CGWindowID> = []
    var closedTabs: [CGWindowID: Date] = [:]
    var tabFollow: (previous: CGWindowID, at: Date)?
    var savedTabs: [SavedTabs] = []
    var savedTabsUntil = Date.distantPast
}
