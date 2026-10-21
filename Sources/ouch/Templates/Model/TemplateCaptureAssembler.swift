import CoreGraphics
import Foundation
import WindowSession

struct TemplateCaptureFacts: @unchecked Sendable {
    var tilingEnabled: Bool
    var displays: [WorkspaceTemplate.Display]
    var zoomed: [String: CGWindowID]
    var order: [CGWindowID]
    var currentSpaces: Set<UInt64>
    var hiddenWorkspaceWindows: Set<CGWindowID>
    var monitorForTiled: [CGWindowID: String]
    var virtualWorkspaces: Bool
    var knownFloating: [CGWindowID: Bool]
    var naturalFrames: [CGWindowID: CGRect]
    var fallbackFocus: CGWindowID?
}

struct TemplateCaptureRequest: @unchecked Sendable {
    var facts: TemplateCaptureFacts
    var apps: [AppSnapshot]
    var frontmostPID: pid_t?
}

enum TemplateWindowCapture {
    static let budget: TimeInterval = 2
    static let backstop: Duration = .milliseconds(2600)
    static let slot = CaptureSlot<WindowBatch>()
}

enum TemplateCaptureAssembler {
    static func make(facts: TemplateCaptureFacts, batch: WindowBatch) throws -> WorkspaceTemplate {
        guard batch.complete else { throw WindowManager.TemplateError.incomplete }
        guard !facts.displays.isEmpty else { throw WindowManager.TemplateError.notReady }
        let focused = batch.focusedID ?? facts.fallbackFocus
        var captured: [WorkspaceTemplate.SavedWindow] = []
        for window in batch.windows {
            if facts.hiddenWorkspaceWindows.contains(window.windowID), !window.fullscreen { continue }
            if !window.spaces.isEmpty, facts.currentSpaces.isDisjoint(with: Set(window.spaces)) { continue }
            let natural = facts.naturalFrames[window.windowID] ?? .null
            let frame = window.fullscreen && !natural.isNull ? natural : window.frame
            guard !frame.isNull, !frame.isEmpty else { continue }
            let floating = facts.knownFloating[window.windowID] ?? window.floatingOverride
            guard let display = display(for: window.windowID, frame: frame, floating: floating, facts: facts) else {
                continue
            }
            captured.append(.init(bundleID: window.bundleID, appName: window.appName, title: window.title,
                                  document: window.document, display: display, frame: frame, floating: floating,
                                  minimized: window.minimized, fullscreen: window.fullscreen,
                                  zoomed: facts.zoomed[display] == window.windowID, focused: focused == window.windowID,
                                  windowID: window.windowID, launchDate: window.launchDate))
        }
        var positions: [CGWindowID: Int] = [:]
        for (index, id) in facts.order.enumerated() where positions[id] == nil { positions[id] = index }
        captured.sort { lhs, rhs in
            let left = positions[lhs.windowID] ?? Int.max
            let right = positions[rhs.windowID] ?? Int.max
            return left == right ? lhs.windowID < rhs.windowID : left < right
        }
        guard !captured.isEmpty else { throw WindowManager.TemplateError.empty }
        return WorkspaceTemplate(name: "", tilingEnabled: facts.tilingEnabled, displays: facts.displays,
                                 windows: captured)
    }

    private static func display(for id: CGWindowID, frame: CGRect, floating: Bool,
                                facts: TemplateCaptureFacts) -> String? {
        if facts.virtualWorkspaces || !floating, let monitor = facts.monitorForTiled[id],
           facts.displays.contains(where: { $0.id == monitor }) { return monitor }
        guard !frame.isNull else { return facts.displays.first?.id }
        return facts.displays.max { lhs, rhs in
            area(lhs.frame.intersection(frame)) < area(rhs.frame.intersection(frame))
        }?.id
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}
