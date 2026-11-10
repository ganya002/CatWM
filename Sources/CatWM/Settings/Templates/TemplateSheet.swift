import CatWMKit
import Combine
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

final class TemplateEditorModel: ObservableObject {
    @Published var name = ""
}

struct TemplatePreviewSheet: View {
    let template: WorkspaceTemplate
    let close: () -> Void

    private var width: CGFloat {
        min(Theme.menuWidth * 4, (NSScreen.main?.visibleFrame.width ?? 1200) - Theme.Space.xxl * 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.large) {
            HStack {
                OButton("Close", variant: .ghost, action: close).keyboardShortcut(.cancelAction)
                Text(template.name).textStyle(.title).oneLine()
                Spacer()
            }
            if let data = template.screenshot, let image = NSImage(data: data) {
                let imageWidth = width - Theme.Space.extraLarge * 2
                let imageHeight = imageWidth * image.size.height / max(image.size.width, 1)
                ScrollView {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: imageWidth, height: imageHeight)
                        .accessibilityLabel("Saved screenshot of \(template.name)")
                }
                .frame(height: min(imageHeight, (NSScreen.main?.visibleFrame.height ?? 800) - Theme.Space.xxl * 5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
            }
            Text(template.summary).textStyle(.caption).foregroundStyle(Theme.inkMuted).oneLine()
        }
        .padding(Theme.Space.extraLarge)
        .frame(width: width)
        .foregroundStyle(Theme.ink)
        .background(Theme.surfaceRaised)
    }
}
