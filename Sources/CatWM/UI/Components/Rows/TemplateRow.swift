import CatWMKit
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
    @State private var menuOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.small) {
            if let screenshot, let image = NSImage(data: screenshot) {
                Button(action: enlarge) {
                    Image(nsImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge preview of \(name)")
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
                            tip: true, action: update)
                    .accessibilityLabel("Update \(name)")
                OIconButton(symbol: "trash", label: "Delete template", variant: .ghostDanger, action: delete)
                    .accessibilityLabel("Delete \(name)")
            }
        }
        .padding(.vertical, Theme.Space.small)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
            .fill(menuOpen ? Theme.hover : .clear))
        .oContextMenu(opened: { menuOpen = $0 }, items: menuItems)
        .disabled(busy)
    }

    private func menuItems() -> [MenuItem] {
        guard !busy else { return [] }
        return [
            MenuItem(id: "open", label: "Open", action: open),
            MenuItem(id: "rename", label: "Rename", action: rename),
            MenuItem(id: "update", label: "Update", action: update),
            .sep("s"),
            MenuItem(id: "delete", kind: .sub, label: "Delete template", danger: true,
                     width: Theme.submenuWidth,
                     children: [MenuItem(id: "delete-confirm", label: "Delete “\(name)”",
                                         danger: true, action: delete)])
        ]
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
                ActionRow(action: QuickAction(id: "template.save.gallery", title: "Save workspace…",
                                              keys: ["S"]) {},
                          hovered: false, pick: {})
                ActionRow(action: QuickAction(id: "template.gallery", title: "Writing",
                                              keys: ["1"], remove: {}, run: {}),
                          hovered: false, remove: {}, pick: {})
                ActionRow(action: QuickAction(id: "template.gallery.hover", title: "Research",
                                              keys: ["2"], remove: {}, run: {}),
                          hovered: true, remove: {}, pick: {})
            }
            .frame(width: Theme.submenuWidth)
        }
    }
}
#endif

struct TemplateSaveRow: View {
    @Binding var name: String
    var busy = false
    var problem: String?
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            OIconButton(symbol: "xmark", label: "Cancel save", action: cancel)
            OTextField(placeholder: "Template name", text: $name, onSubmit: save, autofocus: true)
            OButton("Save", variant: .primary, shortcut: ["↩"], action: save)
                .disabled(busy || problem != nil)
        }
    }
}
