import AppKit
import SwiftUI

func configFill(for config: SavedConfig) -> Color? {
    config.colorHex.flatMap { ConfigLibrary.color(hex: $0) }
}
