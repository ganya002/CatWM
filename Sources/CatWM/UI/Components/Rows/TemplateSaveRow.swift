import SwiftUI

struct TemplateSaveRow: View {
    @Binding var name: String
    var busy = false
    var problem: String?
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            OTextField(placeholder: "Template name", text: $name, onSubmit: save, autofocus: true)
            OButton("Save", variant: .primary, shortcut: ["↩"], action: save)
                .disabled(busy || problem != nil)
            OIconButton(symbol: "xmark", label: "Cancel save", action: cancel)
        }
    }
}
