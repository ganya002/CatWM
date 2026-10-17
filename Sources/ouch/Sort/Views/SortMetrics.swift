import AppKit
import SwiftUI

enum SortMetrics {
    static let lane: CGFloat = 176
    static let rowHeight = Theme.rowHeight
    static let closeExtra = (lane - 16) * 10 / 16 + 8 + 24 + 8
}
