import AppKit
import SwiftUI

struct ConfigTransferMenu: View {
    let kind: ConfigKind
    @ObservedObject var library: ConfigLibrary

    var body: some View {
        OMenuButton(style: OButtonStyle(variant: .secondary, iconOnly: true), items: {
            [
                MenuItem(id: "import", label: "Import config…",
                         action: { library.runImportPanel(only: kind == .full ? nil : kind) }),
                MenuItem(id: "export", label: "Export \(kind == .full ? "full" : kind.title.lowercased()) config…",
                         action: { library.sheet = .export(kind: kind) })
            ]
        }, label: {
            Image(systemName: "square.and.arrow.up.on.square").font(Theme.symbol())
        })
        .fixedSize()
        .tooltip("Import or export").accessibilityLabel("Import or export \(kind.title.lowercased()) config")
    }
}
