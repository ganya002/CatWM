import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

#if DEBUG
@MainActor @Suite struct NativeDesktopQueueTests {
    private func request(_ name: String) -> NativeDesktopController.Request {
        .init(workspace: name, display: "missing-display", space: 1)
    }

    @Test func aFailedSwitchDoesNotDropARequestMadeDuringTheFailure() async {
        let controller = NativeDesktopController()
        var failures = 0
        controller.onFailure = { _ in
            failures += 1
            if failures == 1 { controller.request(self.request("2")) }
        }
        controller.request(request("1"))
        let finished = await poll(2) { !controller.isRunning }
        #expect(finished)
        #expect(failures == 2)
        #expect(controller.requested == nil)
    }
}
#endif
