import AppKit
import CoreText
import SwiftUI

enum Density {
    case extraSmall, small, medium, large, extraLarge

    var radius: CGFloat {
        switch self {
        case .extraSmall: Theme.Radius.medium
        case .small, .medium: Theme.Radius.large
        case .large: Theme.Radius.extraLarge
        case .extraLarge: Theme.Radius.xxl
        }
    }
    var padding: EdgeInsets {
        switch self {
        case .extraSmall: EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8)
        case .small: EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        case .medium: EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        case .large: EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 20)
        case .extraLarge: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        }
    }
    var elevation: Elevation { self == .extraSmall || self == .medium ? .popover : .float }
}
