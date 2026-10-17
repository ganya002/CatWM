import SwiftUI

struct TemplateRow: View {
    let name: String
    let summary: String
    var busy = false
    let open: () -> Void
    let rename: () -> Void
    let update: () -> Void
    let delete: () -> Void

    var body: some View {
        ORow(name, description: summary, symbol: "rectangle.3.group") {
            OButton("Open", icon: "arrow.up.forward.app", size: .sm, action: open)
            OIconButton(symbol: "pencil", label: "Rename template", action: rename)
            OIconButton(symbol: "arrow.triangle.2.circlepath", label: "Save current workspace to this template", action: update)
            OIconButton(symbol: "trash", label: "Delete template", variant: .ghostDanger, action: delete)
        }
        .disabled(busy)
    }
}
