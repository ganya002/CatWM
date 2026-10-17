import AppKit
import SwiftUI

extension EnvironmentValues {
    var keyTile: Bool? {
        get { self[KeyTileKey.self] }
        set { self[KeyTileKey.self] = newValue }
    }
}
