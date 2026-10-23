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
        VStack(alignment: .leading, spacing: Theme.Space.small) {
            if let screenshot, let image = NSImage(data: screenshot) {
                Button(action: enlarge) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge preview of \(name)")
                .help("Click to enlarge")
            } else {
                Text("Update this template to add a screenshot.")
                    .textStyle(.caption).foregroundStyle(Theme.inkMuted)
                    .padding(.vertical, Theme.Space.large)
            }
            ORow(name, description: summary) {
                OButton("Open", icon: "arrow.up.forward.app", size: .small, action: open)
                    .accessibilityLabel("Open \(name)")
                OIconButton(symbol: "pencil", label: "Rename template", action: rename)
                    .accessibilityLabel("Rename \(name)")
                OIconButton(symbol: "arrow.triangle.2.circlepath", label: "Update workspace and screenshot",
                            action: update)
                    .accessibilityLabel("Update \(name)")
                OIconButton(symbol: "trash", label: "Delete template", variant: .ghostDanger, action: delete)
                    .accessibilityLabel("Delete \(name)")
            }
        }
        .padding(.vertical, Theme.Space.small)
        .disabled(busy)
    }
}

#if DEBUG
extension GalleryExamples {
    static let templates = GalleryExample(order: 15) { AnyView(GalleryContent(model: $0).templates) }
}

extension GalleryContent {
    private var templateScreenshot: Data? {
        let sample = HStack(spacing: Theme.Space.small) {
            DemoWindow(app: DemoApp.all[4], main: true)
            VStack(spacing: Theme.Space.small) {
                DemoWindow(app: DemoApp.all[1])
                DemoWindow(app: DemoApp.all[2])
            }
        }
        .padding(Theme.Space.small).frame(width: 560, height: 320).background(Theme.wash)
        return ImageRenderer(content: sample).nsImage?.tiffRepresentation
    }

    @ViewBuilder var templates: some View {
        block("Workspace templates") {
            TemplateRow(name: "Writing", summary: "3 windows · 1 display", screenshot: templateScreenshot,
                        open: {}, rename: {}, update: {}, delete: {})
            TemplateRow(name: "Research", summary: "6 windows · 2 displays", busy: true,
                        open: {}, rename: {}, update: {}, delete: {})
            TemplateSaveRow(name: $model.text, save: {}, cancel: {})
            VStack(spacing: 0) {
                ActionRow(action: QuickAction(id: "template.save.gallery", title: "Save workspace…", symbol: "plus",
                                              keys: ["S"]) {},
                          hovered: false, shown: true, index: 0, pick: {})
                ActionRow(action: QuickAction(id: "template.gallery", title: "Writing", symbol: "rectangle.3.group",
                                              keys: ["1"], remove: {}, run: {}),
                          hovered: false, shown: true, index: 1, remove: {}, pick: {})
                ActionRow(action: QuickAction(id: "template.gallery.hover", title: "Research",
                                              symbol: "rectangle.3.group", keys: ["2"], remove: {}, run: {}),
                          hovered: true, shown: true, index: 2, remove: {}, pick: {})
            }
            .frame(width: Theme.submenuWidth)
        }
    }
}
#endif
