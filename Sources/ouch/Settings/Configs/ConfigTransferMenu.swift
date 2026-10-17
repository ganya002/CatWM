import AppKit
import SwiftUI

struct ConfigTransferMenu: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary

    var body: some View {
        OMenuButton(style: OButtonStyle(variant: .secondary, iconOnly: true), items: {
            [
                MenuItem(id: "import", label: "Import Config…", symbol: "square.and.arrow.down",
                         action: { library.runImportPanel(only: kind == .full ? nil : kind) }),
                MenuItem(id: "export", label: "Export \(kind == .full ? "Full" : kind.title) Config…", symbol: "square.and.arrow.up",
                         action: { library.sheet = .export(kind: kind) }),
            ]
        }) {
            Image(systemName: "square.and.arrow.up.on.square").font(Theme.symbol())
        }
        .fixedSize()
        .tooltip("Import or export").accessibilityLabel("Import or export \(kind.title.lowercased()) config")
    }
}
