import AppKit
import ScreenCaptureKit

enum TemplateScreenshot {
    @MainActor static func capture() async -> Data? {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { return nil }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else { return nil }
            let excluded = content.applications.filter { $0.processID == getpid() }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = min(display.width, 1600)
            configuration.height = max(1, configuration.width * display.height / max(display.width, 1))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            guard !Task.isCancelled else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        } catch {
            return nil
        }
    }
}
