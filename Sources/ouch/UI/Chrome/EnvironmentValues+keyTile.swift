import AppKit
import SwiftUI

extension EnvironmentValues {
    var keyTile: KeyTile {
        get { self[KeyTileKey.self] }
        set { self[KeyTileKey.self] = newValue }
    }
}
