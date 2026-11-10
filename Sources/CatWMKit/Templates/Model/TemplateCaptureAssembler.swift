import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

package struct TemplateCaptureFacts: Sendable {
    package var tilingEnabled: Bool
    package var displays: [WorkspaceTemplate.Display]
    package var zoomed: [String: CGWindowID]
    package var order: [CGWindowID]
    package var currentSpaces: Set<UInt64>
    package var hiddenWorkspaceWindows: Set<CGWindowID>
    package var monitorForTiled: [CGWindowID: String]
    package var virtualWorkspaces: Bool
    package var knownFloating: [CGWindowID: Bool]
    package var naturalFrames: [CGWindowID: CGRect]
    package var fallbackFocus: CGWindowID?
}

package struct TemplateCaptureRequest: Sendable {
    package var facts: TemplateCaptureFacts
    package var apps: [AppSnapshot]
    package var frontmostPID: pid_t?
}

package enum TemplateWindowCapture {
    package static let budget: TimeInterval = 2
    package static let backstop: Duration = .milliseconds(2600)
    package static let slot = CaptureSlot<WindowBatch>()
}

package enum TemplateCaptureAssembler {
    package static func make(facts: TemplateCaptureFacts, batch: WindowBatch) throws -> WorkspaceTemplate {
        guard batch.complete else { throw WindowManager.TemplateError.incomplete }
        guard !facts.displays.isEmpty else { throw WindowManager.TemplateError.notReady }
        let focused = batch.focusedID ?? facts.fallbackFocus
        var captured: [SavedWindow] = []
        for window in batch.windows {
            if facts.hiddenWorkspaceWindows.contains(window.windowID), !window.fullscreen { continue }
            if !window.fullscreen, !window.spaces.isEmpty,
               facts.currentSpaces.isDisjoint(with: Set(window.spaces)) { continue }
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

package enum TemplateScreenshot {
    package static let timeout: Duration = .seconds(4)
    private static let slot = CaptureSlot<Data?>()

    package static func capture() async -> Data? {
        guard case .finished(let data) = await slot.run(within: timeout, operation: { await take() }) else {
            return nil
        }
        return data
    }

    private static func take() async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first else { return nil }
            let excluded = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = min(display.width, 1600)
            configuration.height = max(1, configuration.width * display.height / max(display.width, 1))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        } catch {
            return nil
        }
    }
}
