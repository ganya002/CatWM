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
                    ForEach(shown, id: \.self) { s in
                        Button { selection = s; close() } label: {
                            Image(systemName: s).font(Theme.symbol(Theme.Icon.lg)).frame(width: 34, height: 34)
                                .foregroundStyle(selection == s ? Theme.onAccent : Theme.ink)
                                .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(selection == s ? Theme.accent : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).tooltip(s).accessibilityLabel(s)
                    }
                }
            }
            .frame(height: 190)
            if shown.isEmpty { Text("No icons match").font(Theme.body(12.5)).foregroundStyle(Theme.inkMuted) }
            OButton("Use the default icon", variant: .ghost, size: .sm) { selection = nil; close() }
        }
        .padding(12).frame(width: 300)
    }
}
