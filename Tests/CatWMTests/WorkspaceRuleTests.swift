import AppKit
import CatWMFakes
@testable import CatWMKit
import Foundation
import Testing

private struct RecordedBatch {
    let ids: [CGWindowID]
    let spec: MotionSpec
    let refresh: Int
}

@Suite(.timeLimit(.minutes(1))) @MainActor struct WorkspaceRuleTests {
    private final class Recorder: WindowPresentation {
        var refreshes = 0
        var batches: [RecordedBatch] = []
        func prepare(_ moves: [Animator.Move], spec: MotionSpec) {
            batches.append(RecordedBatch(ids: moves.map(\.window.id), spec: spec, refresh: refreshes))
        }
        func update(_: [CGWindowID: CGRect]) {}
        func cancel(_: CGWindowID) {}
        func close() {}

        func spec(of id: CGWindowID) -> MotionSpec? { batches.first { $0.ids.contains(id) }?.spec }
    }

    private func rules(_ script: String, overrides: (inout Config) -> Void = { _ in }) throws -> Config {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(script)])
        defer { folder.remove() }
        let run = ConfigEngine(entry: folder.entry).run()
        let value = try #require(run.value, "\(run.failures.map(\.text))")
        var config = Config()
        let diagnostics = ConfigScript.read(value, into: &config, file: folder.entry.path)
        overrides(&config)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
        return config
    }

    private func facts(windows: Int = 1, sameApp: Int = 1, apps: [String] = [], name: String = "1") -> WorkspaceFacts {
        var facts = WorkspaceFacts(layout: .bsp, names: [name])
        facts.windows = windows
        facts.sameApp = sameApp
        facts.apps = apps
        return facts
    }

    @Test func laterRulesWinAndOnlyMatchingRulesApply() throws {
        let config = try rules("""
        catwm.workspaces({ windows: { atLeast: 2 } }, () => { catwm.gaps.size = 20; catwm.padding = 3 })
        catwm.workspaces({ windows: { atLeast: 3 } }, () => { catwm.gaps.size = 30 })
        catwm.workspaces({ windows: { atLeast: 2 } }, () => { catwm.gaps.size = 25 })
        catwm.workspaces({ name: "7" }, () => { catwm.gaps.size = 99 })
        """)

        #expect(config.resolved(for: facts(windows: 1)).windowMarginSize == 10)
        let two = config.resolved(for: facts(windows: 2))
        #expect(two.windowMarginSize == 25 && two.paddingLeft == 3)
        #expect(config.resolved(for: facts(windows: 3)).windowMarginSize == 25)
        #expect(config.resolved(for: facts(windows: 1, name: "7")).windowMarginSize == 99)
        #expect(config.windowMarginSize == 10)
    }

    @Test func aRuleBeatsASettingsOverride() throws {
        let config = try rules("catwm.workspaces({ windows: 2 }, () => { catwm.gaps.size = 5 })") {
            $0.windowMarginSize = 12
            $0.animationDuration = 0.3
        }

        #expect(config.resolved(for: facts(windows: 2)).windowMarginSize == 5)
        #expect(config.resolved(for: facts(windows: 2)).animationDuration == 0.3)
        #expect(config.resolved(for: facts(windows: 1)).windowMarginSize == 12)
    }

    @Test func noRulesResolveToTheConfigItself() {
        let config = Config()
        #expect(config.matchingRules(for: facts()).isEmpty)
        #expect(config.resolved(for: facts()).windowMarginSize == config.windowMarginSize)
    }

    private struct World {
        let fake: FakeBackend
        let manager: WindowManager
        let recorder = Recorder()
    }

    private func makeWorld(rule: WorkspaceRule? = nil, screens: Int = 1, animated: Bool = true) -> World {
        let fake = FakeBackend()
        for index in 0..<screens {
            let frame = CGRect(x: CGFloat(index) * 1440, y: 0, width: 1440, height: 900)
            fake.addScreen(frame: frame, visible: frame)
        }
        let manager = fake.makeManager {
            $0.animate = animated
            $0.animationDuration = 0.1
            $0.windowMarginSize = 10
            if let rule { $0.workspaceRules = [rule] }
        }
        let world = World(fake: fake, manager: manager)
        manager.animator.windowPresentation = world.recorder
        manager.onChange = { world.recorder.refreshes += 1 }
        return world
    }

    @Test func aSecondWindowOfOneAppMovesWithTheRulesMotion() async {
        let rule = WorkspaceRule(when: .all([.compare(.sameApp, .atLeast, .int(2))]),
                                 set: ["motion.duration": .number(0.2)])
        let world = makeWorld(rule: rule)
        let first = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        #expect(world.recorder.spec(of: first)?.duration == 0.1)

        world.recorder.batches = []
        let second = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        #expect(world.recorder.spec(of: second)?.duration == 0.2)
    }

    @Test func twoProcessesOfOneAppCountAsOneApp() async {
        let rule = WorkspaceRule(when: .all([.compare(.sameApp, .atLeast, .int(2))]),
                                 set: ["motion.duration": .number(0.2)])
        let world = makeWorld(rule: rule)
        world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))

        world.recorder.batches = []
        let second = world.fake.addWindow(pid: -101, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        #expect(world.recorder.spec(of: second)?.duration == 0.2)
    }

    @Test func aLayoutsRuleSwitchesTheLayoutAndBack() async throws {
        let rule = WorkspaceRule(when: .all([.compare(.windows, .atLeast, .int(2))]),
                                 set: ["layouts": .array([.string("wide")])])
        let world = makeWorld(rule: rule)
        let screen = try #require(world.fake.screens().first)
        let first = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        let base = world.manager.config.layouts.first
        #expect(world.manager.state(for: screen).layout == base)

        let second = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        #expect(world.manager.state(for: screen).layout == .wide)

        world.fake.close(second)
        world.manager.handle(kAXUIElementDestroyedNotification, try #require(world.fake.element(first)))
        #expect(await world.fake.wait(world.manager) { world.manager.state(for: screen).layout == base })
    }

    @Test func aNameMatchesTheWorkspaceLabel() throws {
        let config = try rules("catwm.workspaces({ name: \"Mail\" }, () => { catwm.gaps.size = 4 })")
        var labelled = facts()
        labelled.names = ["1", "Mail"]

        #expect(config.resolved(for: labelled).windowMarginSize == 4)
        #expect(config.resolved(for: facts()).windowMarginSize == 10)
    }

    @Test func aSecondWindowOfAnotherAppDoesNotMatch() async {
        let rule = WorkspaceRule(when: .all([.compare(.sameApp, .atLeast, .int(2))]),
                                 set: ["motion.duration": .number(0.2)])
        let world = makeWorld(rule: rule)
        world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        world.recorder.batches = []
        let other = world.fake.addWindow(pid: -101, bundleID: "test.app.b")
        #expect(await world.fake.settle(world.manager))
        #expect(world.recorder.spec(of: other)?.duration == 0.1)
    }

    @Test func twoScreensAnimateWithTheirOwnMotionInOneRefresh() async throws {
        let rule = WorkspaceRule(when: .all([.compare(.display, .equal, .string("fake-display-2"))]),
                                 set: ["motion.duration": .number(0.4)])
        let world = makeWorld(rule: rule, screens: 2)
        let left = world.fake.addWindow(pid: -100, bundleID: "test.app.a",
                                        frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let right = world.fake.addWindow(pid: -100, bundleID: "test.app.a",
                                         frame: CGRect(x: 1540, y: 100, width: 800, height: 600))
        #expect(await world.fake.settle(world.manager))

        let leftBatch = try #require(world.recorder.batches.first { $0.ids.contains(left) })
        let rightBatch = try #require(world.recorder.batches.first { $0.ids.contains(right) })
        #expect(leftBatch.refresh == rightBatch.refresh)
        #expect(leftBatch.spec.duration == 0.1 && rightBatch.spec.duration == 0.4)
    }

    @Test func aGapsRuleLaysTheWorkspaceOutInTheRefreshThatMatchesIt() async throws {
        let rule = WorkspaceRule(when: .all([.compare(.windows, .atLeast, .int(2))]),
                                 set: ["gaps.enabled": .bool(true), "gaps.size": .number(40)])
        let world = makeWorld(rule: rule, animated: false)
        let first = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        #expect(await world.fake.settle(world.manager))
        #expect(world.manager.targets[first]?.width == 1440)

        world.fake.clearWrites()
        let second = world.fake.addWindow(pid: -101, bundleID: "test.app.b")
        #expect(await world.fake.settle(world.manager))
        let one = try #require(world.manager.targets[first]), two = try #require(world.manager.targets[second])
        #expect(one.width + two.width + 40 == 1440)
        #expect(abs(one.maxX - two.minX) == 40 || abs(two.maxX - one.minX) == 40)
        let sizes = world.fake.writes.compactMap { write -> CGSize? in
            if case .size(first, let size) = write { size } else { nil }
        }
        #expect(!sizes.isEmpty && sizes.allSatisfy { $0.width == one.width })
    }

    @Test func minimisedWindowsDoNotCount() async throws {
        let rule = WorkspaceRule(when: .all([.compare(.windows, .atLeast, .int(2))]),
                                 set: ["gaps.enabled": .bool(true), "gaps.size": .number(40)])
        let world = makeWorld(rule: rule)
        let first = world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        let second = world.fake.addWindow(pid: -101, bundleID: "test.app.b")
        world.fake.minimize(second)
        await withCheckedContinuation { continuation in world.manager.scanAndRefresh { continuation.resume() } }
        #expect(world.manager.targets[first]?.width == 1440)

        world.fake.minimize(second, false)
        #expect(await world.fake.settle(world.manager))
        let width = try #require(world.manager.targets[first]).width
        #expect(width < 1440)
    }

    @Test func aWindowOnScreenCountsWhetherItTilesOrFloats() async throws {
        let rule = WorkspaceRule(when: .all([.compare(.windows, .equal, .int(2))]),
                                 set: ["motion.duration": .number(0.3)])
        let world = makeWorld(rule: rule)
        world.fake.addWindow(pid: -100, bundleID: "test.app.a")
        let floating = world.fake.addWindow(pid: -101, bundleID: "test.app.b")
        #expect(await world.fake.settle(world.manager))
        try #require(world.manager.windows[floating]).userFloating = .chosen(true)
        world.manager.refresh()
        #expect(world.manager.config(for: world.manager.shown.values.first).animationDuration == 0.3)
    }
}
