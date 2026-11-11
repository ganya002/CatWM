import AppKit
import os
import ScreenCaptureKit

package final class ScreenRecording: Sendable {
    package static let shared = ScreenRecording()
    private static let testDoneKey = "screenRecordingTestDone"

    private struct State {
        var granted = false
        var checking = false
        var watching = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    package var watching: Bool {
        get { state.withLock { $0.watching } }
        set { state.withLock { $0.watching = newValue } }
    }

    package var isGranted: Bool { state.withLock { $0.granted } || CGPreflightScreenCaptureAccess() }
    @MainActor package var isTestDone: Bool { Instance.defaults.bool(forKey: Self.testDoneKey) }

    package func refresh() {
        let start = state.withLock { state in
            guard state.watching, !state.granted, !state.checking,
                  !CGPreflightScreenCaptureAccess() else { return false }
            state.checking = true
            return true
        }
        guard start else { return }
        Task {
            let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let granted = content != nil
            state.withLock { state in
                state.granted = granted
                state.checking = false
                if state.granted { state.watching = false }
            }
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
