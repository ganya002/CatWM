import AppKit
import SwiftUI

enum KeyTile: Equatable {
    case rise
    case tile(shown: Bool)

    var shown: Bool {
        switch self {
        case .rise: true
        case let .tile(shown): shown
        }
    }

    var style: PanelMotion { self == .rise ? .rise : .tile }
}

struct KeyTileKey: EnvironmentKey { static let defaultValue = KeyTile.rise }
