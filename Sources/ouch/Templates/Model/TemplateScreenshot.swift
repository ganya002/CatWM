import AppKit
import ScreenCaptureKit

enum TemplateScreenshot {
    static let timeout: Duration = .seconds(4)
    private static let slot = TemplateCaptureSlot<Data?>()

    static func capture() async -> Data? {
        guard case .finished(let data) = await slot.run(within: timeout, operation: { await take() }) else {
            return nil
        }
        return data
    }

    private static func take() async -> Data? {
        let allowed = await MainActor.run { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
        guard allowed else { return nil }
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
