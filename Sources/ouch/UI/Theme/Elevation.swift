import AppKit
import CoreText
import SwiftUI

enum Elevation {
    case sm, knob, popover, float

    var radius: CGFloat {
        switch self {
        case .sm: 1
        case .knob: 2
        case .popover: 13
        case .float: 22
        }
    }

    var y: CGFloat {
        switch self {
        case .sm: 1
        case .knob: 0
        case .popover: 10
        case .float: 18
        }
    }

    var room: CGFloat { radius * 2 + y }
}
