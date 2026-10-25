import AppKit
import SwiftUI

func configInk(for config: SavedConfig) -> Color {
    guard let hex = config.colorHex else { return Theme.ink }
    return ConfigLibrary.prefersDarkText(hex: hex) ? Color.black.opacity(0.85) : .white
}
