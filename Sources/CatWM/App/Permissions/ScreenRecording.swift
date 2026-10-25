import AppKit
import os
import ScreenCaptureKit

final class ScreenRecording {
    static let shared = ScreenRecording()
    private static let testDoneKey = "screenRecordingTestDone"
    private let grantedLive = OSAllocatedUnfairLock(initialState: false)
    private var checking = false
    var watching = false

    var isGranted: Bool { grantedLive.withLock { $0 } || CGPreflightScreenCaptureAccess() }
    var isTestDone: Bool { UserDefaults.standard.bool(forKey: Self.testDoneKey) }

    func refresh() {
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
    func takeTestImage() async -> Bool {
        guard isGranted else { return false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return false }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 64
            configuration.height = 64
            _ = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            UserDefaults.standard.set(true, forKey: Self.testDoneKey)
            Log.info("screen recording test image taken")
            return true
        } catch {
            Log.info("screen recording test image failed: \(error.localizedDescription)")
            return false
        }
    }
}
