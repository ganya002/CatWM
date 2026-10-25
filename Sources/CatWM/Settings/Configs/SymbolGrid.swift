import AppKit
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
