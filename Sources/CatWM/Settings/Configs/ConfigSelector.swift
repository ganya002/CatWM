import AppKit
import CatWMKit
import SwiftUI

struct ConfigSelector: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary
    var width: CGFloat?
    @StateObject private var pop = PopoverFlag()
    @StateObject private var hover = Flag()

    var body: some View {
        let config = library.current(kind)
        let ink = configInk(for: config)
        Button { pop.open.toggle() } label: {
            HStack(spacing: 6) {
                ConfigGlyph(config: config, size: 13, tint: ink)
                Text(config.name).font(Theme.body(13, .medium)).oneLine().foregroundStyle(ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.extraSmall, .semibold))
                    .foregroundStyle(ink.opacity(0.7))
            }
            .padding(.leading, 6).padding(.trailing, 12).frame(width: width, height: Theme.controlHeight)
            .background(Capsule().fill(configFill(for: config) ?? (hover.isOn ? Theme.wellHover : Theme.well)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale(scale: 0.96))
        .onHover { hover.isOn = $0 }
        .accessibilityLabel("\(kind.title) config: \(config.name)")
        .oPopover(isPresented: $pop.open) { ConfigList(kind: kind, library: library, dismiss: { pop.open = false }) }
    }
}

final class PopoverFlag: ObservableObject { @Published var open = false }

func configFill(for config: SavedConfig) -> Color? {
    config.colorHex.flatMap { ConfigLibrary.color(hex: $0) }
}

func configInk(for config: SavedConfig) -> Color {
    guard let hex = config.colorHex else { return Theme.ink }
    return ConfigLibrary.prefersDarkText(hex: hex) ? Color.black.opacity(0.85) : .white
}

struct ConfigGlyph: View {
    let config: SavedConfig
    var size: CGFloat = 16
    var tint: Color = Theme.ink

    var body: some View {
        if config.isBuiltIn, config.symbol == nil {
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
