import AppKit
@testable import CatWM
@testable import CatWMKit
import QuartzCore
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct DesktopMotionTests {
    private let settings = NativeDesktopController.Settings(duration: 0.12, curve: .easeOut, bounce: 0.5)

    @Test func disabledAnimationStillSubmitsOnlyTheFinalPoseAfterPreparation() async throws {
        let motion = DesktopMotion(screen: try #require(NSScreen.screens.first))
        try await motion.frames(2)
        var values: [Double] = []
        let immediate = NativeDesktopController.Settings(duration: 0, curve: .easeOut, bounce: 0.5)
        try await motion.animate(from: 0, to: 1, with: immediate) { values.append($0) }
        #expect(values == [1])
    }

    @Test func cancellationAfterPreparationDoesNotSubmitMotion() async throws {
        let motion = DesktopMotion(screen: try #require(NSScreen.screens.first))
        var values: [Double] = []
        let task = Task { @MainActor in
            try await motion.frames(2)
            withUnsafeCurrentTask { $0?.cancel() }
            try await motion.animate(from: 0, to: 1, with: settings) { values.append($0) }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(values.allSatisfy { $0 == 0 })
    }

    @Test func anExpiredPreparedFrameKeepsTheFullAnimation() async throws {
        let screen = try #require(NSScreen.screens.first)
        let motion = DesktopMotion(screen: screen)
        try await motion.frames(2)
        try await DesktopMotion(screen: screen).frames(2)
        var values: [Double] = []
        let start = CACurrentMediaTime()
        try await motion.animate(from: 0, to: 1, with: settings) { values.append($0) }
        #expect(values.first == 0 && values.last == 1)
        #expect(CACurrentMediaTime() - start >= 0.09)
    }
}
