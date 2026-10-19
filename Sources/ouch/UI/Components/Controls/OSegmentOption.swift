import AppKit
import SwiftUI

struct OSegmentOption<T: Hashable> {
    let value: T
    var label: String
    var keys: String?
    var count: Int?
    var help: String?
}
