import AppKit
import CatWMKit
import SwiftUI

final class CursorActions {
    static let shared = CursorActions()

    let model = CursorActionsModel()
    var dotPanel: NSPanel?
    var menuPanel: NSPanel?
    var moveTap: CFMachPort?
    var moveSource: CFRunLoopSource?
    weak var rowHover: NSView?
    var pointerInRows = false
    var pointerAnchor = CGPoint.zero
    var pointerNoteQueued = false
    var lastFollow = CGPoint(x: -1, y: -1)
    var shown = false
    var opening = false
    var closeWork: DispatchWorkItem?
    var screenshotTask: Task<Void, Never>?
    static let dotSize = CursorActionsView.markSize

    var enabled: Bool { WindowManager.shared.config.cursorActions }
    var isMenuOpen: Bool { model.open }
}

struct QuickAction: Identifiable {
    let id: String
    let title: String
    var keys: [String] = []
    var keyCode: UInt16?
    var keyMods: CGEventFlags = []
    var isOn = false
    var destructive = false
    var remove: (() -> Void)?
    let run: () -> Void
}

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
    var onPick: ((QuickAction) -> Void)?
    var onDelete: ((QuickAction) -> Void)?
    var onSave: (() -> Void)?
    var onCancelSave: (() -> Void)?

    var nameProblem: String? {
        templateDraft.flatMap { TemplateLibrary.shared.nameProblem(templateName, id: $0.id) }
    }
}

func cursorMoveCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                        refcon _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        CursorActions.shared.reenableMoveTap()
    } else {
        CursorActions.shared.follow(cgPoint: event.location)
    }
    return Unmanaged.passUnretained(event)
}
