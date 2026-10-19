import AppKit
import SwiftUI

enum MenuRowHighlight: Equatable {
    case followsHover
    case fixed(Bool)

    func isLit(hovering: Bool) -> Bool {
        switch self {
        case .followsHover: hovering
        case let .fixed(lit): lit
        }
    }
}
