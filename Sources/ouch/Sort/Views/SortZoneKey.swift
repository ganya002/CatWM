import AppKit
import SwiftUI

struct SortZoneKey: PreferenceKey {
    static var defaultValue: [SortZone: CGRect] = [:]
    static func reduce(value: inout [SortZone: CGRect], nextValue: () -> [SortZone: CGRect]) { value.merge(nextValue()) { $1 } }
}
