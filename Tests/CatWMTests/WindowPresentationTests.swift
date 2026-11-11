import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@MainActor struct WindowPresentationTests {
    final class Presentation: WindowPresentation {
        var prepared: [CGWindowID] = []
        var cancelled: [CGWindowID] = []
        var frames: [[CGWindowID: CGRect]] = []
        var closed = false
        func prepare(_ moves: [Animator.Move], spec _: MotionSpec) { prepared += moves.map(\.window.id) }
        func update(_ frames: [CGWindowID: CGRect]) { self.frames.append(frames) }
        func cancel(_ id: CGWindowID) { cancelled.append(id) }
        func close() { closed = true }
    }

    @Test func cancelledMotionCancelsItsPresentationAndEmptyBatchesLeaveItAlone() async throws {
        let backend = FakeBackend()
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let id = backend.addWindow(frame: frame)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        window.remember(frame)
        let presentation = Presentation()
        var animator: Animator? = Animator(backend: backend)
        animator?.windowPresentation = presentation
        animator?.animate([.init(window: window, to: frame.insetBy(dx: -100, dy: 0), bounds: frame)], duration: 1)
        #expect(presentation.prepared == [id])
        let cancellations = presentation.cancelled.count
        animator?.animate([], duration: 0)
        #expect(presentation.cancelled.count == cancellations)
        #expect(presentation.prepared == [id])
        animator?.cancel(id)
        #expect(presentation.cancelled.count == cancellations + 1)
        animator = nil
        await withCheckedContinuation { turn in DispatchQueue.main.async { turn.resume() } }
        #expect(presentation.closed)
    }

    @Test func finalNativeWriteRetiresThePresentation() async throws {
        let backend = FakeBackend()
        let id = backend.addWindow()
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        window.remember(CGRect(x: 100, y: 100, width: 400, height: 300))
        let animator = Animator(backend: backend)
        let presentation = Presentation()
        animator.windowPresentation = presentation
        animator.animate([.init(window: window, to: CGRect(x: 100, y: 100, width: 700, height: 300),
                                bounds: CGRect(x: 0, y: 0, width: 1200, height: 900))], duration: 0)
        #expect(await animator.waitForPendingWrites(pids: [-100]))
        #expect(presentation.frames.last?.isEmpty == true)
    }

    @Test func splitDraggingUpdatesThePresentationBeforeTheAppReplies() throws {
        let backend = FakeBackend()
        let source = CGRect(x: 100, y: 100, width: 400, height: 300)
        let id = backend.addWindow(frame: source)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        window.remember(source)
        let animator = Animator(backend: backend)
        let presentation = Presentation()
        animator.windowPresentation = presentation
        let target = CGRect(x: 100, y: 100, width: 600, height: 300)
        defer { animator.cancel(id) }
        animator.follow([.init(window: window, to: target, bounds: target)])
        #expect(presentation.prepared == [id])
        #expect(presentation.frames.last?[id] == target)
    }
}
