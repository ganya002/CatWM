import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_TEST_WINDOW_SERVER"] == "1"), .serialized)
struct NativePlacementTests {
    private struct Fixture {
        let manager: WindowManager
        let window: Window
        let frame: CGRect
        let request: NativeDesktopController.Request
    }

    private func fixture(id: CGWindowID = .max - 30) throws -> Fixture {
        _ = NSApplication.shared
        let screen = try #require(Screen.all().first)
        let manager = WindowManager(config: .parse(defaultText))
        manager.tilingEnabled = true
        let window = Window(id: id, element: AXUIElementCreateApplication(-1), pid: -1, bundleID: nil)
        manager.windows[window.id] = window
        manager.observedApps = [(pid: window.pid, bundleID: nil)]
        manager.order = [window.id]
        manager.model.assign(window.id, to: "test")
        let targets = manager.layoutTargets([window.id], manager.state(workspace: "test"), on: screen)
        let frame = try #require(targets?[window.id])
        window.remember(frame)
        return Fixture(manager: manager, window: window, frame: frame,
                       request: .init(workspace: "test", display: screen.uuid, space: 0))
    }

    @Test(arguments: [0.0, 1.0])
    func matchingRecordedAndServerFramesDoNotWriteToTheApp(clientRounding: Double) async throws {
        let test = try fixture()
        var actual = test.frame
        actual.size.width -= clientRounding
        test.window.remember(actual)
        var writers = 0
        test.manager.animator = Animator(makeWriter: { writers += 1; return AXWriter(pid: $0) })
        try await test.manager.prepareNativeLayout(test.request, readFrames: { ids in
            #expect(ids == [test.window.id])
            return [test.window.id: actual]
        })
        #expect(writers == 0)
        #expect(test.manager.targets[test.window.id] == test.frame)
    }

    @Test func aRealWindowAlreadyInItsSlotDoesNotNeedAnAXWriter() async throws {
        let focus = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.level = .normal
        defer { panel.close() }
        let test = try fixture(id: CGWindowID(panel.windowNumber))
        let height = try #require(NSScreen.screens.first).frame.height
        panel.setFrame(CGRect(x: test.frame.minX, y: height - test.frame.maxY,
                              width: test.frame.width, height: test.frame.height), display: false)
        panel.orderFrontRegardless()
        let ready = await poll(1) {
            WindowServerQuery.frames(for: [test.window.id])?[test.window.id]?.approxEqual(test.frame) == true
        }
        #expect(ready)
        var writers = 0
        test.manager.animator = Animator(makeWriter: { writers += 1; return AXWriter(pid: $0) })
        var samples: [Double] = []
        for _ in 0..<30 {
            let start = ProcessInfo.processInfo.systemUptime
            try await test.manager.prepareNativeLayout(test.request)
            samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        samples.sort()
        print("native unchanged preparation: median \(samples[15]) ms p95 \(samples[28]) ms, writers \(writers)")
        #expect(writers == 0)
        #expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == focus)
    }

    enum Mismatch { case recorded, server, unavailable }

    @Test(arguments: [Mismatch.recorded, .server, .unavailable])
    func eitherMismatchOrAnUnavailableServerStillPlacesTheWindow(_ mismatch: Mismatch) async throws {
        let test = try fixture()
        if mismatch == .recorded { test.window.remember(test.frame.offsetBy(dx: 20, dy: 0)) }
        var writers = 0
        test.manager.animator = Animator(makeWriter: { writers += 1; return AXWriter(pid: $0) })
        try await test.manager.prepareNativeLayout(test.request, readFrames: { _ in
            if mismatch == .unavailable { return nil }
            return [test.window.id: mismatch == .server ? test.frame.offsetBy(dx: 20, dy: 0) : test.frame]
        })
        #expect(writers == 1)
    }

    @Test func aPendingWriteMustFinishBeforeTheUnchangedFrameCheck() async throws {
        let test = try fixture()
        let writer = AXWriter(pid: -1)
        let release = DispatchSemaphore(value: 0)
        writer.run {
            _ = release.wait(timeout: .now() + 30)
            test.window.remember(test.frame.offsetBy(dx: 20, dy: 0))
        }
        test.manager.animator = Animator(makeWriter: { _ in writer })
        test.manager.animator.position(test.window, at: test.frame)
        var released = false
        let delayedRelease = Task { @MainActor in
            released = true
            release.signal()
        }
        defer { delayedRelease.cancel(); release.signal() }
        try await test.manager.prepareNativeLayout(test.request, readFrames: { _ in
            #expect(released)
            #expect(test.window.cachedFrame != test.frame)
            return [test.window.id: test.frame]
        })
        #expect(writer.takeStats().land.count == 1)
    }
}
