import AppKit
import CoreText
import SwiftUI

enum TextStyle {
    case largeTitle
    case title
    case sectionTitle
    case caption

    var font: Font {
        switch self {
        case .largeTitle: Theme.display(40)
        case .title: Theme.body(22)
        case .sectionTitle: Theme.body(12, .medium)
        case .caption: Theme.body(12)
        }
    }
    var tracking: CGFloat {
        switch self {
        case .largeTitle: -1
        case .title: -0.2
        case .sectionTitle: 0.24
        case .caption: 0
        }
    }
}
