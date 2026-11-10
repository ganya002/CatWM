import AppKit
@testable import CatWMKit
import Foundation
import Testing

extension CatWMEngineTests {
    @Test func optionsDescribeTheConfig() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default { gaps: { size: 12 } }"))
        let size = try #require(engine.options.first { $0.id == "gaps.size" })
        #expect(size.kind == .number)
        #expect(size.range == 0...100)
        #expect(size.value == .int(12))
        #expect(size.defaultValue != .int(12))
        let curve = try #require(engine.options.first { $0.id == "animation.curve" })
        #expect(curve.kind == .string)
        let keys = try #require(engine.options.first { $0.id == "features.input.keys" })
        #expect(keys.kind == .bool && keys.defaultValue == false && keys.value == false)
        #expect(keys.feature == "features.windows.tiling")
        let swaps = try #require(engine.options.first { $0.id == "mouse.swapsWindows" })
        #expect(swaps.feature == "features.input.mouse")
        await cleanUp(engine)
    }

    @Test func overridesSurviveAConfigChangeUntilReset() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default { gaps: { size: 4 } }"))
        try engine.setOption("gaps.size", to: 20)
        #expect(engine.options.first { $0.id == "gaps.size" }?.value == .int(20))
        try engine.replaceConfig("export default { gaps: { size: 6 } }")
        #expect(engine.options.first { $0.id == "gaps.size" }?.value == .int(20))
        #expect(engine.overrides == ["gaps": ["size": 20]])
        #expect(throws: CatWMEngine.EngineError.self) { try engine.setOption("gaps.size", to: "wide") }
        #expect(throws: CatWMEngine.EngineError.unknownOption("gaps.width")) {
            try engine.setOption("gaps.width", to: 3)
        }
        try engine.resetOption("gaps.size")
        #expect(engine.options.first { $0.id == "gaps.size" }?.value == .int(6))
        #expect(engine.overrides.isEmpty)
        await cleanUp(engine)
    }

    @Test func aFeatureOverrideStartsTiling() async throws {
        let engine = try makeEngine()
        _ = fake.addScreen()
        _ = fake.addWindow()
        try engine.start(config: .text("export default { animation: { enabled: false } }"))
        #expect(!engine.snapshot().isTiling)
        try engine.setOption("features.windows.tiling", to: true)
        #expect(engine.snapshot().isTiling)
        #expect(await fake.settle(WindowManager.shared))
        try engine.setOption("features.windows.tiling", to: false)
        #expect(await fake.wait(WindowManager.shared) { !engine.snapshot().isTiling })
        await cleanUp(engine)
    }

    @Test func turningTabGroupsOffSplitsTheGroups() async throws {
        let engine = try makeEngine()
        let screen = fake.addScreen()
        let first = fake.addWindow(), second = fake.addWindow()
        try engine.start(config: .text(Self.tiling))
        try engine.setOption("features.windows.tabGroups", to: true)
        let manager = WindowManager.shared
        #expect(await fake.settle(manager))
        manager.joinTab(second, onto: first)
        #expect(await fake.settle(manager))
        #expect(manager.tabs.group(of: first)?.members == [first, second])
        try engine.setOption("features.windows.tabGroups", to: false)
        #expect(await fake.settle(manager))
        #expect(manager.tabs.isEmpty)
        #expect(fake.frame(of: first).width == screen.visible.width / 2)
        #expect(fake.frame(of: second).width == screen.visible.width / 2)
        await cleanUp(engine)
    }

    @Test func aBrokenChangeKeepsTheLastGoodConfig() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default { gaps: { size: 4 } }"))
        #expect(throws: CatWMEngine.EngineError.self) { try engine.replaceConfig("export default { gaps: { size: } }") }
        #expect(engine.options.first { $0.id == "gaps.size" }?.value == .int(4))
        #expect(!engine.snapshot().diagnostics.isEmpty)
        await cleanUp(engine)
    }

    @Test func loadConfigReadsAHostFile() async throws {
        let engine = try makeEngine()
        try engine.start(config: .text("export default {}"))
        let folder = home.appendingPathComponent("host")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "export const size = 9\n".write(to: folder.appendingPathComponent("size.ts"), atomically: true,
                                              encoding: .utf8)
        let entry = folder.appendingPathComponent("host.config.ts")
        try "import { size } from './size'\nexport default { gaps: { size } }\n"
            .write(to: entry, atomically: true, encoding: .utf8)
        try engine.loadConfig(at: entry)
        #expect(engine.options.first { $0.id == "gaps.size" }?.value == .int(9))
        await cleanUp(engine)
    }
}
