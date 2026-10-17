import SwiftUI

struct TemplatesPane: View {
    @ObservedObject var doc: ConfigDocument
    @ObservedObject var ui: SettingsUI
    @ObservedObject private var library = TemplateLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Save the windows and layout of your current workspace. Open a template from here or from quick actions.")
                    .font(Theme.body()).foregroundStyle(Theme.inkMuted)
                OButton("Save workspace…", icon: "plus", variant: .primary) { library.beginSave() }
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
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        TemplateRow(name: template.name, summary: template.summary, busy: library.restoring,
                                    open: { library.restore(template) }, rename: { library.draft = template },
                                    update: { library.update(template) }, delete: { library.delete(template) })
                        Text(template.displays.map { "\($0.name) · \(Int($0.frame.width)) × \(Int($0.frame.height))" }.joined(separator: " · "))
                            .textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
                            .padding(.bottom, Theme.Space.sm)
                    }
                }
            }
            .setting("templates.saved", ui)

            OGroup("Quick actions") {
                OptionSwitch(\.cursorActions, doc: doc, ui: ui)
                Text("In window mode, tap the mode modifier to open templates at the pointer. Press S to save, 1–9 to open, or comma to manage templates.")
                    .font(Theme.body()).foregroundStyle(Theme.inkMuted).padding(.vertical, Theme.Space.sm)
            }

            OGroup("What a template restores") {
                Text("Templates save apps, window positions and sizes, display sizes, layouts, and floating, tiled, minimized, zoomed, or full screen states.")
                    .font(Theme.body()).foregroundStyle(Theme.inkMuted).padding(.vertical, Theme.Space.sm)
                Text("Ouch reuses matching windows and opens missing apps. It reopens documents when an app supplies a document address. Other windows stay open.")
                    .font(Theme.body()).foregroundStyle(Theme.inkMuted).padding(.vertical, Theme.Space.sm)
                Text("Tabs, unsaved work, and other app contents may need your attention. Missing displays use an available display, with window sizes adjusted to fit.")
                    .font(Theme.body()).foregroundStyle(Theme.inkMuted).padding(.vertical, Theme.Space.sm)
            }
        }
    }
}
