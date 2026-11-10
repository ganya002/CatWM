import CatWMKit
import SwiftUI

struct TemplatesPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var settingsUI: SettingsUI
    @ObservedObject private var library = TemplateLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.extraLarge) {
            if let error = library.error { OStatus(kind: .danger, text: error) }
            if library.restoring {
                ORow("Opening template", description: library.status) {
                    OButton("Stop", variant: .ghost) { library.cancelRestore() }
                }
            } else if let status = library.status { OStatus(kind: .info, text: status) }

            OGroup("Saved templates") {
                if library.templates.isEmpty {
                    ORow("No templates yet",
                         description: "In window mode, open cursor actions and choose Save workspace.") { EmptyView() }
                }
                ForEach(library.templates) { template in
                    TemplateRow(name: template.name, summary: template.summary, screenshot: template.screenshot,
                                busy: library.restoring || library.updating,
                                enlarge: { library.preview = template },
                                open: { library.restore(template) }, rename: { library.draft = template },
                                update: { library.update(template) }, delete: { library.delete(template) })
                }
            }
            .setting(Self.searchSaved.id, settingsUI)

            OGroup("Apps") {
                OptionRows(pane: .templates, section: "Apps", doc: doc, settingsUI: settingsUI)
            }
        }
        .sheet(item: $library.preview) { template in
            TemplatePreviewSheet(template: template) { library.preview = nil }
        }
    }

    static let searchSaved = SettingEntry(id: "templates.saved", title: "Saved workspace templates", pane: .templates,
                                          keywords: "open restore rename delete displays quick actions")
}
