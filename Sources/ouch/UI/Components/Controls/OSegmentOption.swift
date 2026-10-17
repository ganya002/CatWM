import AppKit
import SwiftUI

struct OSegmentOption<T: Hashable> {
    let value: T
    var label: String
    var keys: String? = nil
    var count: Int? = nil
    var help: String? = nil
}
