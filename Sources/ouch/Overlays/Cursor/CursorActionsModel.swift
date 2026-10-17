import AppKit

final class CursorActionsModel: ObservableObject {
    @Published var title = ""
    @Published var actions: [QuickAction] = []
    @Published var hovered: String?
    @Published var keyboardHover: String?
    @Published var trackPointer = false
    @Published var modGlyph = "⌥"
    @Published var open = false
    @Published var anchor = CGPoint.zero
    @Published var templateDraft: WorkspaceTemplate?
    @Published var templateName = ""
    @Published var snapshotReady = false
    @Published var capturing = false
    @Published var saveError: String?
    var previewJob: TemplatePreviewJob?
    var snapshotTask: Task<Void, Never>?
    var templateSaveGeneration = 0
    var hoverArm = 0
    var onPick: ((QuickAction) -> Void)?
    var onDelete: ((QuickAction) -> Void)?
    var onSave: (() -> Void)?
    var onCancelSave: (() -> Void)?

    var nameProblem: String? {
        templateDraft.flatMap { TemplateLibrary.shared.nameProblem(templateName, id: $0.id) }
    }
}
