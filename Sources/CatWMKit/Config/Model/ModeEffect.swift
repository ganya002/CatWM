import Foundation

package enum ModeEffect: String, CaseIterable {
    case draw, ripple, corners, none

    package var title: String {
        switch self {
        case .draw: "Draw"
        case .ripple: "Ripple"
        case .corners: "Corners"
        case .none: "None"
        }
    }
}
