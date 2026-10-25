import AppKit
import os
import ScreenCaptureKit

enum ScreenRecording {
    private static let testDoneKey = "screenRecordingTestDone"
    private struct Check { var grantedLive = false, checking = false, watching = false }
    private static let check = OSAllocatedUnfairLock(initialState: Check())

    static var isGranted: Bool { check.withLock { $0.grantedLive } || CGPreflightScreenCaptureAccess() }
    static var isTestDone: Bool { UserDefaults.standard.bool(forKey: testDoneKey) }

    static func watch() { check.withLock { $0.watching = true } }

    static func refresh() {
        guard check.withLock({ $0.watching && !$0.checking }), !isGranted else { return }
        check.withLock { $0.checking = true }
        Task { @MainActor in
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let granted = content != nil
            check.withLock { check in
                check.grantedLive = granted
                check.checking = false
                if granted { check.watching = false }
            }
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
