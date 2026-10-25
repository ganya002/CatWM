import AppKit
import SwiftUI

struct CategoryAnchor: PreferenceKey {
    static var defaultValue: [MenuCategory: Anchor<CGRect>] = [:]
    static func reduce(value: inout [MenuCategory: Anchor<CGRect>], nextValue: () -> [MenuCategory: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
