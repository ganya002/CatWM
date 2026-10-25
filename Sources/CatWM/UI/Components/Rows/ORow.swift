import AppKit
import SwiftUI

struct ORow<Control: View>: View {
    let label: String
    var description: String?
    var symbol: String?
    @ViewBuilder var control: Control
    @Environment(\.isEnabled) private var enabled

    init(_ label: String, description: String? = nil, symbol: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.description = description
        self.symbol = symbol
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol).font(Theme.symbol(Theme.Icon.large)).foregroundStyle(Theme.inkMuted)
                    .frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Theme.body(14)).foregroundStyle(Theme.ink).oneLine()
                if let description {
                    Text(description).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                }
            }
            .opacity(enabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { control }.fixedSize()
        }
        .frame(minHeight: 44)
        .padding(.vertical, 4)
    }
}

#if DEBUG
extension GalleryContent {
    @ViewBuilder var rowExamples: some View {
        ORow("Animation curve", symbol: "wand.and.stars") {
            OSegmented(title: "Curve", options: ["Ease", "Spring", "Off"].map { ($0, $0) }, selection: $model.segment)
        }
        ORow("Enter window mode", symbol: "keyboard") { Kbd(keys: ["⌘", "⇪"]) }
    }
}
#endif
