import AppKit
import SwiftUI

struct SortDrag {
    let item: SortItem
    let closing: Bool
    var location: CGPoint
    let grab: CGSize
    var id: CGWindowID { item.id }
}
