import SwiftUI

struct TemplateSheet: View {
    let template: WorkspaceTemplate
    @StateObject private var model = TemplateEditorModel()
    @ObservedObject var library: TemplateLibrary

    private var problem: String? { library.nameProblem(model.name, id: template.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.large) {
            Text(library.templates.contains { $0.id == template.id } ? "Rename template" : "Save workspace template")
                .textStyle(.title).oneLine()
            Text(template.summary).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
            OTextField(placeholder: "Template name", text: $model.name, onSubmit: save, autofocus: true)
            if !model.name.isEmpty, let problem { OStatus(kind: .warning, text: problem) }
            if let error = library.error { OStatus(kind: .danger, text: error) }
            HStack(spacing: Theme.Space.small) {
                Spacer()
                OButton("Cancel", variant: .ghost) { library.draft = nil }.keyboardShortcut(.cancelAction)
                OButton("Save", variant: .primary, shortcut: ["↩"], action: save)
                    .keyboardShortcut(.defaultAction).disabled(problem != nil)
            }
        }
        .padding(Theme.Space.extraLarge)
        .frame(width: Theme.menuWidth + Theme.Space.xxl * 4)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
        .onAppear { model.name = template.name }
    }

    private func save() {
        guard problem == nil else { return }
        var updated = template
        updated.name = model.name
        if library.save(updated) {
            library.status = "Saved \(model.name.trimmingCharacters(in: .whitespacesAndNewlines))."
            library.draft = nil
        }
    }
}
