import SwiftUI

struct TemplateRow: View {
    let name: String
    let summary: String
    var screenshot: Data?
    var busy = false
    var enlarge: () -> Void = {}
    let open: () -> Void
    let rename: () -> Void
    let update: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            if let screenshot, let image = NSImage(data: screenshot) {
                Button(action: enlarge) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge preview of \(name)")
                .help("Click to enlarge")
            } else {
                Text("Update this template to add a screenshot.")
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    .padding(.vertical, Theme.Space.lg)
            }
            ORow(name, description: summary) {
                OButton("Open", icon: "arrow.up.forward.app", size: .sm, action: open)
                OIconButton(symbol: "pencil", label: "Rename template", action: rename)
                OIconButton(symbol: "arrow.triangle.2.circlepath", label: "Update workspace and screenshot", action: update)
                OIconButton(symbol: "trash", label: "Delete template", variant: .ghostDanger, action: delete)
            }
        }
        .padding(.vertical, Theme.Space.sm)
        .disabled(busy)
    }
}
