import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

struct ColorFillSizingTests {
    private func item(from: CGRect, to target: CGRect, fill: Bool = true) throws -> Animator.Item {
        let backend = FakeBackend()
        let id = backend.addWindow(frame: from)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        var item = Animator.Item(move: .init(window: window, to: target, bounds: from.union(target)),
                                 from: from, start: 0, spec: .init(duration: 1, curve: .linear, bounce: 0))
        if fill { item.colorSizing = ColorFillSizing(source: from, target: target) }
        return item
    }

    @Test func shrinkingFollowsThePredictedSizeInsideTheColorViewport() throws {
        let source = CGRect(x: 0, y: 38, width: 1000, height: 600)
        let target = CGRect(x: 0, y: 38, width: 700, height: 600)
        let item = try item(from: source, to: target)
        for time in [0.01, 0.2, 0.5, 0.9, 1.0] {
            let viewport = item.frame(at: time, aligned: false)
            let native = item.request(at: time + 0.03, presentedAt: time)
            #expect(native.size == item.frame(at: time + 0.03).size)
            #expect(viewport.contains(native))
        }
    }

    @Test func shrinkingWritesIntermediateNativeSizesBeforeLanding() async throws {
        let source = CGRect(x: 0, y: 38, width: 1000, height: 600)
        let target = CGRect(x: 0, y: 38, width: 700, height: 600)
        let item = try item(from: source, to: target)
        let window = item.move.window
        let backend = try #require(window.backend as? FakeBackend)
        window.remember(source)
        let writer = AXWriter(pid: window.pid, backend: backend)
        backend.clearWrites()
        for time in [0.01, 0.2, 0.5, 0.9] {
            writer.step(window) { _ in item.request(at: time + 0.03, presentedAt: time) }
            await withCheckedContinuation { continuation in writer.run { continuation.resume() } }
        }
        await withCheckedContinuation { continuation in
            writer.land(window, at: target) { _ in continuation.resume() }
        }
        #expect(backend.frame(of: window.id) == target)
        let sizes = backend.writes.compactMap { write -> CGSize? in
            if case let .size(_, size) = write { return size }
            return nil
        }
        #expect(sizes.map(\.width) == [988, 931, 841, 721, 700])
    }

    @Test func predictionShrinksAheadWithoutJumpingToTheDestination() throws {
        let item = try item(from: CGRect(x: 0, y: 38, width: 1000, height: 800),
                            to: CGRect(x: 0, y: 38, width: 700, height: 600))
        let current = item.request(at: 0.25, presentedAt: 0.25)
        let predicted = item.request(at: 0.30, presentedAt: 0.25)
        #expect(predicted.width < current.width && predicted.width > 700)
        #expect(predicted.height < current.height && predicted.height > 600)
        #expect(item.frame(at: 0.25, aligned: false).contains(predicted))
    }

    @Test func growthCannotPredictBeyondTheVisibleViewport() throws {
        let item = try item(from: CGRect(x: 910, y: 38, width: 800, height: 600),
                            to: CGRect(x: 850, y: 38, width: 860, height: 600))
        for time in [0.01, 0.1, 0.25, 0.5, 0.9] {
            let viewport = item.frame(at: time, aligned: false)
            let native = item.request(at: time + 0.05, presentedAt: time)
            #expect(viewport.contains(native))
            #expect(native.maxX <= 1710)
        }
    }

    @Test func aMovingShrinkerPredictsItsPositionInsideTheViewport() throws {
        let item = try item(from: CGRect(x: 850, y: 38, width: 860, height: 600),
                            to: CGRect(x: 910, y: 38, width: 800, height: 600))
        for time in [0.01, 0.1, 0.25, 0.5, 0.9] {
            let viewport = item.frame(at: time, aligned: false)
            let native = item.request(at: time + 0.05, presentedAt: time)
            #expect(native.size == item.frame(at: time + 0.05).size)
            #expect(viewport.contains(native))
        }
    }

    @Test func missingColorPresentationKeepsOrdinaryPredictiveMotion() throws {
        let item = try item(from: CGRect(x: 910, y: 38, width: 800, height: 600),
                            to: CGRect(x: 850, y: 38, width: 860, height: 600), fill: false)
        #expect(item.request(at: 0.3, presentedAt: 0.25) == item.frame(at: 0.3))
    }
}
