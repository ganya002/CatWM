import CoreGraphics
import Foundation

package struct TabInteraction {
    package var minimizingTabs: Set<Int> = []
    package let drag = TabDrag()
    package var parkedTabs: Set<CGWindowID> = []
    package var closedTabs: [CGWindowID: Date] = [:]
    package var tabFollow: (previous: CGWindowID, at: Date)?
    package var savedTabs: [SavedTabs] = []
    package var savedTabsUntil = Date.distantPast
}
