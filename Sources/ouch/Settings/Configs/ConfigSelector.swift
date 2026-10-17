import AppKit
import SwiftUI

struct ConfigSelector: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary
    var width: CGFloat? = nil
    @StateObject private var pop = PopoverFlag()
    @StateObject private var hover = Flag()

    var body: some View {
        let c = library.current(kind)
        let fg = configInk(for: c)
        Button { pop.open.toggle() } label: {
            HStack(spacing: 6) {
                ConfigGlyph(config: c, size: 13, tint: fg)
                Text(c.name).font(Theme.body(13, .medium)).oneLine().foregroundStyle(fg)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(Theme.symbol(Theme.Icon.xs, .semibold)).foregroundStyle(fg.opacity(0.7))
            }
            .padding(.leading, 6).padding(.trailing, 12).frame(width: width, height: Theme.controlHeight)
            .background(Capsule().fill(configFill(for: c) ?? (hover.on ? Theme.wellHover : Theme.well)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressScale(scale: 0.96))
        .onHover { hover.on = $0 }
        .accessibilityLabel("\(kind.title) config: \(c.name)")
        .oPopover(isPresented: $pop.open) { ConfigList(kind: kind, library: library, dismiss: { pop.open = false }) }
    }
}
