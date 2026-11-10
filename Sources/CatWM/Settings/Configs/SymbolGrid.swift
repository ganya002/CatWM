import AppKit
import CatWMKit
import SwiftUI

struct SymbolGrid: View {
    @Binding var selection: String?
    let close: () -> Void
    private final class Query: ObservableObject { @Published var text = "" }
    @StateObject private var query = Query()

    private var shown: [String] {
        query.text.isEmpty ? curatedSymbols : curatedSymbols.filter { $0.localizedCaseInsensitiveContains(query.text) }
    }

    var body: some View {
        VStack(spacing: 8) {
            OTextField(placeholder: "Search icons", text: $query.text)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 7), spacing: 4) {
                    ForEach(shown, id: \.self) { symbol in
                        Button { selection = symbol; close() } label: {
                            Image(systemName: symbol).font(Theme.symbol(Theme.Icon.large)).frame(width: 34, height: 34)
                                .foregroundStyle(selection == symbol ? Theme.onAccent : Theme.ink)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                                    .fill(selection == symbol ? Theme.accent : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(symbol)
                    }
                }
            }
            .frame(height: 190)
            if shown.isEmpty { Text("No icons match").textStyle(.caption).foregroundStyle(Theme.inkMuted) }
            OButton("Use the default icon", variant: .ghost, size: .small) { selection = nil; close() }
        }
        .padding(12).frame(width: 300)
    }
}

let curatedSymbols: [String] = [
    "star.fill", "bolt.fill", "flame.fill", "leaf.fill", "heart.fill", "moon.fill", "sun.max.fill", "cloud.fill",
    "drop.fill", "snowflake", "sparkles", "wand.and.stars", "paintbrush.fill", "paintpalette.fill", "bucket.fill",
    "gamecontroller.fill", "keyboard", "command", "option", "control", "laptopcomputer", "desktopcomputer", "display",
    "macwindow", "square.grid.2x2.fill", "rectangle.split.3x1.fill", "sidebar.left", "slider.horizontal.3",
    "gearshape.fill", "wrench.fill", "hammer.fill", "briefcase.fill", "book.fill", "graduationcap.fill", "pencil",
    "terminal.fill", "chevron.left.forwardslash.chevron.right", "cpu.fill", "hare.fill", "tortoise.fill", "airplane",
    "car.fill", "bicycle", "figure.run", "music.note", "headphones", "film.fill", "camera.fill", "photo.fill",
    "theatermasks.fill", "crown.fill", "trophy.fill", "flag.fill", "bell.fill", "bookmark.fill", "tag.fill", "pin.fill",
    "lock.fill", "key.fill", "globe", "map.fill", "cube.fill", "shippingbox.fill", "puzzlepiece.fill",
    "lightbulb.fill", "atom", "pawprint.fill", "tree.fill", "mountain.2.fill", "wind", "rainbow", "party.popper.fill"
].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
