import AppKit
import ScreenCaptureKit

enum ScreenRecording {
    private static let testDoneKey = "screenRecordingTestDone"
    private static var grantedLive = false
    private static var checking = false
    static var watching = false

    static var isGranted: Bool { grantedLive || CGPreflightScreenCaptureAccess() }
    static var isTestDone: Bool { UserDefaults.standard.bool(forKey: testDoneKey) }

    static func refresh() {
        guard watching, !isGranted, !checking else { return }
        checking = true
        Task { @MainActor in
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            grantedLive = content != nil
            checking = false
            if grantedLive { watching = false }
        }
    }

    @MainActor
    static func takeTestImage() async -> Bool {
        guard isGranted else { return false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 64
            configuration.height = 64
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            UserDefaults.standard.set(true, forKey: testDoneKey)
            Log.info("screen recording test image taken")
            return true
        } catch {
            Log.info("screen recording test image failed: \(error.localizedDescription)")
            return false
        }
    }
}
