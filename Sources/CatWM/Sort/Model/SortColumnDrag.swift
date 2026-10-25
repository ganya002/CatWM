import AppKit
import SwiftUI

struct SortColumnDrag {
    let lane: SortLane
    let ratio: CGFloat
    let mainCount: Int
    var location: CGPoint
    let grab: CGSize
}
