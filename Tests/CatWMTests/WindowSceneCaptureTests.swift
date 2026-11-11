import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

struct WindowSceneCaptureTests {
    @MainActor @Test func cancellingOneLiveParticipantKeepsTheOtherNativeTrajectory() throws {
        let backend = FakeBackend()
        let sources = [CGRect(x: 0, y: 38, width: 600, height: 400),
                       CGRect(x: 610, y: 38, width: 600, height: 400)]
        let windows = try sources.map { source in
            let id = backend.addWindow(frame: source)
            let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                                bundleID: nil, backend: backend)
            window.remember(source)
            return window
        }
        let frames = Dictionary(uniqueKeysWithValues: zip(windows.map(\.id), sources))
        let capture = WindowSceneCapture(displays: [], images: [:], order: windows.map(\.id), excluded: [])
        let scene = WindowResizeScene(capture: capture, frames: frames, live: WindowLiveBuffers())
        let animator = Animator(backend: backend)
        animator.makeResizeScene = { _ in scene }
        defer { windows.forEach { animator.cancel($0.id) } }
        let target = CGRect(x: 510, y: 38, width: 700, height: 400)
        animator.animate([.init(window: windows[0], to: CGRect(x: 0, y: 38, width: 500, height: 400),
                                bounds: sources[0]),
                          .init(window: windows[1], to: target, bounds: target)], duration: 1)
        #expect(scene.visible)
        animator.cancel(windows[0].id)
        #expect(!scene.visible)
        #expect(!animator.isAnimating(windows[0].id))
        #expect(animator.isMoving(windows[1].id, to: target))
    }

    @MainActor @Test func anEmptyInstantBatchKeepsTheActiveResizeScene() throws {
        let backend = FakeBackend()
        let from = CGRect(x: 100, y: 100, width: 600, height: 400)
        let target = CGRect(x: 100, y: 100, width: 800, height: 600)
        let id = backend.addWindow(frame: from)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        window.remember(from)
        let capture = WindowSceneCapture(displays: [], images: [:], order: [id], excluded: [])
        let scene = WindowResizeScene(capture: capture, frames: [id: from])
        let animator = Animator(backend: backend)
        animator.makeResizeScene = { _ in scene }
        defer { animator.cancel(id) }
        animator.animate([.init(window: window, to: target, bounds: target)], duration: 1)
        #expect(scene.visible)
        animator.animate([], duration: 0)
        #expect(scene.visible)
        #expect(animator.isMoving(id, to: target))
    }

    @Test func splitHandlesDoNotOccludeTilesButForegroundWindowsStillDo() {
        let tile = CGRect(x: 0, y: 25, width: 600, height: 875)
        let handle = CGRect(x: 591, y: 25, width: 18, height: 875)
        let floating = CGRect(x: 100, y: 100, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: handle, 3: floating]
        #expect(WindowSceneCapture.unobscured([tile], participants: [1], excluding: [2],
                                             order: [2, 1], frame: { frames[$0] }))
        #expect(!WindowSceneCapture.unobscured([tile], participants: [1], excluding: [2],
                                              order: [2, 3, 1], frame: { frames[$0] }))
        #expect(!WindowSceneCapture.unobscured([tile], participants: [1], excluding: [2],
                                              order: [2], frame: { frames[$0] }))
    }

    @Test func foregroundWindowsKeepTheirOcclusionDuringResize() {
        let tile = CGRect(x: 100, y: 100, width: 600, height: 400)
        let floating = CGRect(x: 150, y: 150, width: 200, height: 100)
        let frames: [CGWindowID: CGRect] = [1: tile, 2: floating]
        #expect(!WindowSceneCapture.unobscured([tile], participants: [1], order: [2, 1], frame: { frames[$0] }))
        #expect(WindowSceneCapture.unobscured([tile], participants: [1], order: [1, 2], frame: { frames[$0] }))
        #expect(WindowSceneCapture.unobscured([tile], participants: [1, 2], order: [2, 1], frame: { frames[$0] }))
        #expect(WindowSceneCapture.unobscured([tile.offsetBy(dx: 800, dy: 0)], participants: [1],
                                             order: [2, 1], frame: { frames[$0] }))
        #expect(!WindowSceneCapture.unobscured([tile], participants: [1], order: [2], frame: { frames[$0] }))
    }

    private var screen: Screen {
        Screen(id: 1, uuid: "test", frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
               visible: CGRect(x: 0, y: 25, width: 1200, height: 875), isBuiltin: true, nsScreen: nil)
    }

    @Test func proxyMotionKeepsSubpixelSamplesWhileAXFramesStayAligned() throws {
        let backend = FakeBackend()
        let from = CGRect(x: 100, y: 100, width: 800, height: 600)
        let target = CGRect(x: 300, y: 200, width: 1000, height: 800)
        let id = backend.addWindow(frame: from)
        let window = Window(id: id, element: try #require(backend.element(id)), pid: -100,
                            bundleID: nil, backend: backend)
        let item = Animator.Item(move: .init(window: window, to: target, bounds: target), from: from,
                                 start: 0, spec: .init(duration: 1, curve: .linear, bounce: 0))
        #expect(abs(item.frame(at: 0.123, aligned: false).minX - 124.6) < 0.0001)
        #expect(item.frame(at: 0.123).minX == 125)
        #expect(item.frame(at: 1, aligned: false) == target)
    }

    @Test func adjacentTilesCanBeCapturedWithoutDuplicatingTheirContents() {
        let first = CGRect(x: 0, y: 25, width: 600, height: 875)
        let second = CGRect(x: 600, y: 25, width: 600, height: 875)
        #expect(WindowSceneCapture.canCapture([first, second], on: [screen]))
        #expect(!WindowSceneCapture.canCapture([first, second.offsetBy(dx: -20, dy: 0)], on: [screen]))
    }

    @Test func partiallyOffscreenSourcesUseLiveWindowsInsteadOfCroppedSnapshots() {
        let frame = CGRect(x: -20, y: 25, width: 600, height: 875)
        #expect(!WindowSceneCapture.canCapture([frame], on: [screen]))
        #expect(!WindowSceneCapture.canCapture([.null], on: [screen]))
        #expect(!WindowSceneCapture.canCapture([.zero], on: [screen]))
        #expect(!WindowSceneCapture.canCapture([], on: [screen]))
    }

    @Test func sourcesOnSeparateDisplaysAreSupportedWithoutCapturingAcrossTheirEdges() {
        let other = Screen(id: 2, uuid: "other", frame: CGRect(x: 1200, y: 0, width: 1200, height: 900),
                           visible: CGRect(x: 1200, y: 25, width: 1200, height: 875), isBuiltin: false, nsScreen: nil)
        let frames = [CGRect(x: 0, y: 25, width: 600, height: 800),
                      CGRect(x: 1200, y: 25, width: 600, height: 800)]
        #expect(WindowSceneCapture.canCapture(frames, on: [screen, other]))
        #expect(!WindowSceneCapture.canCapture([CGRect(x: 1100, y: 25, width: 600, height: 800)],
                                               on: [screen, other]))
    }
}
