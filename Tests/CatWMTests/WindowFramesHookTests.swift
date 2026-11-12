import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@MainActor struct WindowFramesHookTests {
    @Test func theHostSeesTheMovingFrameAndThenTheWindowDropsOut() async throws {
        let backend = FakeBackend()
        let source = CGRect(x: 100, y: 100, width: 400, height: 300)
        let id = backend.addWindow(frame: source)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        window.remember(source)
        let animator = Animator(backend: backend)
        var calls: [[CGWindowID: CGRect]] = []
        animator.onFrames = { calls.append($0) }
        let target = CGRect(x: 100, y: 100, width: 600, height: 300)
        animator.follow([.init(window: window, to: target, bounds: target)])
        #expect(calls.last?[id] == target)

        animator.endFollow()
        #expect(await animator.waitForPendingWrites(pids: [-100]))
        #expect(calls.last?.isEmpty == true)
        #expect(animator.windowPresentation == nil)
    }
}
