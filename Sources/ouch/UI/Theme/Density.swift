import AppKit
import CoreText
import SwiftUI

enum Density {
    case xs, sm, md, lg, xl

    var radius: CGFloat {
        switch self {
        case .xs: Theme.Radius.md
        case .sm, .md: Theme.Radius.lg
        case .lg: Theme.Radius.xl
        case .xl: Theme.Radius.xxl
        }
    }
    var padding: EdgeInsets {
        switch self {
        case .xs: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        case .sm: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .md: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .lg: EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)
        case .xl: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        }
    }
    var elevation: Elevation { self == .xs || self == .md ? .popover : .float }
}
