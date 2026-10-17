import AppKit
import SwiftUI

struct ConfigGlyph: View {
    let config: SavedConfig
    var size: CGFloat = 16
    var tint: Color = Theme.ink

    var body: some View {
        if config.isBuiltIn {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().interpolation(.high)
                .frame(width: size * 1.7, height: size * 1.7)
        } else {
            Image(systemName: config.symbol ?? config.kind.genericSymbol)
                .font(Theme.symbol(size * 0.92, .semibold))
                .foregroundStyle(tint)
                .frame(width: size * 1.7, height: size * 1.7)
        }
    }
}
