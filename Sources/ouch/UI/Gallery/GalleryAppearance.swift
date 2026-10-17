#if DEBUG

import AppKit
import SwiftUI

enum GalleryAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

#endif
