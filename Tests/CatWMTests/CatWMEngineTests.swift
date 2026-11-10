import AppKit
@testable import CatWMKit
import Foundation
import Testing

@Suite(.serialized, .timeLimit(.minutes(1))) @MainActor struct CatWMEngineTests {
    let home = URL(fileURLWithPath: "/tmp/cw-\(UUID().uuidString.prefix(6))")
    let fake = FakeBackend()

    static let tiling = """
        export default {
          features: { windows: { tiling: true } },
          animation: { enabled: false },
          gaps: { enabled: false },
          padding: 0,
          focus: { mouseFollowsFocus: false, followsMouse: false },
        }
        """

    func makeEngine(granted: Set<Permission> = [.accessibility]) throws -> CatWMEngine {
        let paths = try #require(InstancePaths(id: "embed-test", home: home))
        let defaults = try #require(UserDefaults(suiteName: "catwm-test-\(UUID())"))
        return CatWMEngine(paths: paths, defaults: defaults, backend: fake, permissions: { granted })
    }

    var socket: String {
        home.appendingPathComponent(".config/catwm/instances/embed-test/catwm.sock").path
    }

    func cleanUp(_ engine: CatWMEngine) async {
        await engine.stop()
        try? FileManager.default.removeItem(at: home)
    }

    @Test func everyFeatureStartsOff() async throws {
        let engine = try makeEngine()
        let window = fake.addWindow(frame: CGRect(x: 10, y: 10, width: 300, height: 200))
        _ = fake.addScreen()
        try engine.start(config: .text("export default {}"))
        let snapshot = engine.snapshot()
        #expect(snapshot.isRunning)
        #expect(!snapshot.isTiling)
        #expect(snapshot.features.isEmpty)
        #expect(snapshot.windows == .array([]))
        #expect(!FileManager.default.fileExists(atPath: socket))
        #expect(Hotkeys.shared.tap == nil)
        #expect(fake.frame(of: window) == CGRect(x: 10, y: 10, width: 300, height: 200))
        await cleanUp(engine)
    }

    @Test func tilingTilesTheWindows() async throws {
        let engine = try makeEngine()
        let screen = fake.addScreen()
        let first = fake.addWindow(), second = fake.addWindow()
        try engine.start(config: .text(Self.tiling))
        #expect(engine.snapshot().isTiling)
        #expect(await fake.settle(WindowManager.shared))
        #expect(fake.frame(of: first).width == screen.visible.width / 2)
        #expect(fake.frame(of: second).width == screen.visible.width / 2)
        #expect(engine.snapshot().windows.array?.count == 2)
        await cleanUp(engine)
    }

    @Test func aSecondStartFails() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default {}"))
        #expect(throws: CatWMEngine.EngineError.alreadyRunning) { try engine.start(config: .text("export default {}")) }
        let other = try makeEngine()
        #expect(throws: CatWMEngine.EngineError.alreadyRunning) { try other.start(config: .text("export default {}")) }
        await cleanUp(engine)
    }

    @Test func aSecondEngineLeavesTheRunningOneInPlace() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default {}"))
        let running = WindowManager.shared
        let other = try makeEngine()
        #expect(throws: CatWMEngine.EngineError.alreadyRunning) { try other.start(config: .text("export default {}")) }
        #expect(WindowManager.shared === running)
        await cleanUp(engine)
    }

    @Test func tilingWaitsForAccessibility() async throws {
        let engine = try makeEngine(granted: [])
        try engine.start(config: .text("export default {}"))
        try engine.setOption("features.windows.tiling", to: true)
        #expect(engine.snapshot().features == ["features.windows.tiling"])
        #expect(!engine.snapshot().isTiling)
        #expect(WindowManager.shared.notificationObservers.isEmpty)
        await cleanUp(engine)
    }

    @Test func stopTearsDownAndStartWorksAgain() async throws {
        let engine = try makeEngine()
        let screen = fake.addScreen()
        _ = fake.addWindow()
        try engine.start(config: .text(Self.tiling))
        let first = WindowManager.shared
        #expect(await fake.settle(first))
        #expect(!first.notificationObservers.isEmpty)

        await engine.stop()
        #expect(!engine.isRunning)
        #expect(!first.isStarted && !first.servicesStarted)
        #expect(first.notificationObservers.isEmpty)
        #expect(first.eventMonitors.isEmpty)
        #expect(first.observers.isEmpty)
        let late = fake.addWindow(frame: CGRect(x: 5, y: 5, width: 700, height: 500))
        await withCheckedContinuation { done in first.scanAndRefresh { done.resume() } }
        #expect(fake.frame(of: late) == CGRect(x: 5, y: 5, width: 700, height: 500))

        try engine.start(config: .text(Self.tiling))
        #expect(WindowManager.shared !== first)
        #expect(await fake.settle(WindowManager.shared))
        #expect(fake.frame(of: late).width == screen.visible.width / 2)
        await cleanUp(engine)
    }

    @Test func aBrokenConfigFailsTheStart() async throws {
        let engine = try makeEngine()
        #expect {
            try engine.start(config: .text("export default { features: { windows: { tiling: true } }, gaps: 4 }"))
        } throws: { error in
            guard case .config(let problems) = error as? CatWMEngine.EngineError else { return false }
            return problems.first?.message.contains("`gaps`") == true
        }
        #expect(!engine.isRunning)
        #expect(!engine.snapshot().isTiling)
        #expect(engine.snapshot().diagnostics.first?.message.contains("`gaps`") == true)
        try engine.start(config: .text("export default {}"))
        await cleanUp(engine)
    }

    @Test func presentationIsNotAvailable() async throws {
        let engine = try makeEngine()
        #expect {
            try engine.start(config: .text("export default { features: { presentation: { hud: true } } }"))
        } throws: { error in
            guard case .config(let problems) = error as? CatWMEngine.EngineError else { return false }
            return problems.contains { $0.message.contains("isn't available in embedded mode") }
        }
        #expect(!engine.options.contains { $0.id.hasPrefix("features.presentation") || $0.id.hasPrefix("switcher") })
        await cleanUp(engine)
    }

    @Test func eventsReportConfigChanges() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default { gaps: { size: 4 } }"))
        let events = engine.events()
        try engine.replaceConfig("export default { gaps: { size: 5 } }")
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.name == "config.reloaded")
        #expect(event?.data == ["errors": []])
        await engine.stop()
        #expect(await iterator.next() == nil)
        try? FileManager.default.removeItem(at: home)
    }

    @Test func performRunsCommandsWithTheAccessChecks() async throws {
        let engine = try makeEngine()
        let screen = fake.addScreen()
        _ = fake.addWindow()
        try engine.start(config: .text(Self.tiling))
        #expect(await fake.settle(WindowManager.shared))
        #expect(try engine.perform("windows").array?.count == 1)
        try engine.perform("layout", ["layout": "wide"])
        #expect(try engine.perform("screens").array?.first?["layout"] == "wide")
        #expect(screen.visible.width > 0)
        #expect(throws: CatWMEngine.EngineError.command(code: "forbidden",
                                                        message: "`exec` is only allowed from keybinds")) {
            try engine.perform("dispatch", ["dispatcher": "exec", "arg": "true"])
        }
        #expect {
            try engine.perform("dispatch", ["dispatcher": "exit"])
        } throws: { error in
            guard case .command(_, let message) = error as? CatWMEngine.EngineError else { return false }
            return message.contains("embedded mode")
        }
        #expect {
            try engine.perform("dispatch", ["dispatcher": "moveintogroup", "arg": "left"])
        } throws: { error in
            guard case .command(_, let message) = error as? CatWMEngine.EngineError else { return false }
            return message.contains("features.windows.tabGroups")
        }
        await cleanUp(engine)
    }

    @Test func theSocketFeatureListensOnTheEnginePath() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default { features: { services: { socket: true } } }"))
        #expect(FileManager.default.fileExists(atPath: socket))
        await cleanUp(engine)
    }

    @Test func snapshotReportsThePermissions() async throws {
        let engine = try makeEngine(granted: [.accessibility, .screenRecording])
        try engine.start(config: .text("export default {}"))
        #expect(engine.snapshot().permissions == ["accessibility": true, "inputMonitoring": false,
                                                  "screenRecording": true, "fullDiskAccess": false])
        await cleanUp(engine)
    }
}
