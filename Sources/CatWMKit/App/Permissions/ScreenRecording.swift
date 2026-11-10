import AppKit
import os
import ScreenCaptureKit

package final class ScreenRecording {
    package static let shared = ScreenRecording()
    private static let testDoneKey = "screenRecordingTestDone"
    private let grantedLive = OSAllocatedUnfairLock(initialState: false)
    private var checking = false
    package var watching = false

    package var isGranted: Bool { grantedLive.withLock { $0 } || CGPreflightScreenCaptureAccess() }
    package var isTestDone: Bool { Instance.defaults.bool(forKey: Self.testDoneKey) }

    package func refresh() {
        guard watching, !isGranted, !checking else { return }
        checking = true
        Task { @MainActor in
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let granted = content != nil
            grantedLive.withLock { $0 = granted }
            checking = false
            if granted { watching = false }
        }
    }

    @MainActor
    package func takeTestImage() async -> Bool {
        guard isGranted else { return false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 64
            configuration.height = 64
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            Instance.defaults.set(true, forKey: Self.testDoneKey)
            Log.info("screen recording test image taken")
            return true
        } catch {
            Log.info("screen recording test image failed: \(error.localizedDescription)")
            return false
        }
    }
}
