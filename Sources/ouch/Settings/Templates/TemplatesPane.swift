import SwiftUI

struct TemplatesPane: View {
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = TemplateLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            OGroup {
                ORow("Save workspace template") {
                    OButton("Save…", icon: "plus", size: .sm) { library.beginSave() }
                }
                .disabled(!ui.status.trusted || library.restoring)
            }
            .setting("templates.save", ui)

            if let error = library.error { OStatus(kind: .danger, text: error) }
            if library.restoring {
                ORow("Opening template", description: library.status) {
                    OButton("Stop", variant: .ghost) { library.cancelRestore() }
                }
            } else if let status = library.status { OStatus(kind: .info, text: status) }

            OGroup("Saved templates") {
                if library.templates.isEmpty {
                    ORow("No templates yet", description: "Arrange your windows, then save your workspace.") { EmptyView() }
                }
                ForEach(library.templates) { template in
                    TemplateRow(name: template.name, summary: template.summary, busy: library.restoring,
                                open: { library.restore(template) }, rename: { library.draft = template },
                                update: { library.update(template) }, delete: { library.delete(template) })
                }
            }
            .setting("templates.saved", ui)
        }
    }
}
