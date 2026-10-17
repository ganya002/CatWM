import SwiftUI

struct TemplatesPane: View {
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = TemplateLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            if let error = library.error { OStatus(kind: .danger, text: error) }
            if library.restoring {
                ORow("Opening template", description: library.status) {
                    OButton("Stop", variant: .ghost) { library.cancelRestore() }
                }
            } else if let status = library.status { OStatus(kind: .info, text: status) }

            OGroup("Saved templates") {
                if library.templates.isEmpty {
                    ORow("No templates yet", description: "In window mode, open cursor actions and choose Save workspace.") { EmptyView() }
                }
                ForEach(library.templates) { template in
                    TemplateRow(name: template.name, summary: template.summary, screenshot: template.screenshot,
                                busy: library.restoring || library.updating,
                                enlarge: { library.preview = template },
                                open: { library.restore(template) }, rename: { library.draft = template },
                                update: { library.update(template) }, delete: { library.delete(template) })
                }
            }
            .setting("templates.saved", ui)
        }
        .sheet(item: $library.preview) { template in
            TemplatePreviewSheet(template: template) { library.preview = nil }
        }
    }
}
