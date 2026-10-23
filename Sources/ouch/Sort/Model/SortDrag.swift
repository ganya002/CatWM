import AppKit
import SwiftUI

struct SortDrag {
    let item: SortItem
    let closing: Bool
    var location: CGPoint
    let grab: CGSize
    var group: [SortItem] = []
    var id: CGWindowID { item.id }

    func carries(_ other: CGWindowID) -> Bool { other == id || group.contains { $0.id == other } }
}
