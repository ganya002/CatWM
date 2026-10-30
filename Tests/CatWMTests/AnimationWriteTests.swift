import AppKit
@testable import CatWM
import Testing

struct AnimationWriteTests {
    private func drain(_ writer: AXWriter) async {
        await withCheckedContinuation { continuation in
            writer.run { continuation.resume() }
        }
    }

    @Test(arguments: [0.12, 0.5])
    func repeatedPixelFramesDoNotWritePositions(duration: Double) async throws {
        let backend = FakeBackend()
        let start = CGRect(x: 100, y: 100, width: 800, height: 600)
        let id = backend.addWindow(frame: start)
        let element = try #require(backend.element(id))
        let window = Window(id: id, element: element, pid: -100, bundleID: nil, backend: backend)
        window.remember(start)
        let writer = AXWriter(pid: window.pid, backend: backend)
        let target = start.offsetBy(dx: 20, dy: 0)
        let item = Animator.Item(move: .init(window: window, to: target, bounds: target), from: start,
                                 start: 0, duration: duration, curve: .easeOut, bounce: 0)
        var previous = start
        var changedFrames = 0
        let steps = Int(ceil(duration * 120))
        for step in 0..<steps {
            let frame = item.frame(at: Double(step) / 120)
            if frame != previous { changedFrames += 1 }
            previous = frame
            writer.step(window) { _ in frame }
            await drain(writer)
            #expect(backend.frame(of: id) == frame)
        }
        let positions = backend.writes.filter { if case .position = $0 { return true }; return false }
        #expect(positions.count == changedFrames)
        #expect(changedFrames < steps)
        await withCheckedContinuation { continuation in
            writer.land(window, at: target) { wrote in
                #expect(wrote)
                continuation.resume()
            }
        }
        #expect(backend.frame(of: id) == target)
        #expect(backend.writes.last == .position(id, target.origin))
    }

    @Test func changedObservedFrameIsWrittenAgain() async throws {
        let backend = FakeBackend()
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)
        let id = backend.addWindow(frame: frame)
        let element = try #require(backend.element(id))
        let window = Window(id: id, element: element, pid: -100, bundleID: nil, backend: backend)
        window.remember(frame)
        let writer = AXWriter(pid: window.pid, backend: backend)
        writer.step(window) { _ in frame }
        await drain(writer)
        let moved = frame.offsetBy(dx: 40, dy: 0)
        backend.userMoves(id, to: moved)
        window.remember(moved)
        backend.clearWrites()
        writer.step(window) { _ in frame }
        await drain(writer)
        #expect(backend.frame(of: id) == frame)
        #expect(backend.writes.contains(.position(id, frame.origin)))
        writer.cancel(id)
        await drain(writer)
    }
}
