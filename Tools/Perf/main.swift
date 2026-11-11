import CatWMFakes
import CatWMKit
import Darwin
import Foundation

struct Usage {
    let cpu: Double
    let footprint: Double
    let peak: Double

    private static let tick: Double = {
        var base = mach_timebase_info_data_t()
        mach_timebase_info(&base)
        return Double(base.numer) / Double(base.denom)
    }()

    static func now() -> Usage {
        var info = rusage_info_v4()
        withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                _ = proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        let megabyte = 1024.0 * 1024.0
        return Usage(cpu: Double(info.ri_user_time + info.ri_system_time) * tick / 1e6,
                     footprint: Double(info.ri_phys_footprint) / megabyte,
                     peak: Double(info.ri_lifetime_max_phys_footprint) / megabyte)
    }
}

@MainActor final class Scenario {
    var samples: [String: [Double]] = [:]
    let fake = FakeBackend()

    func record(_ metric: String, _ value: Double) { samples[metric, default: []].append(value) }

    func windows(_ count: Int, apps: Int = 5) {
        for index in 0..<count { fake.addWindow(pid: pid_t(-100 - index % apps)) }
    }

    func settled(_ manager: WindowManager) async {
        guard await fake.settle(manager) else { fail("the windows did not settle") }
    }

    func idle(seconds: Int, metric: String) async throws {
        for _ in 0..<seconds {
            let start = Usage.now().cpu
            try await Task.sleep(for: .seconds(1))
            record(metric, Usage.now().cpu - start)
        }
    }

    func run(_ name: String) async throws {
        fake.addScreen()
        switch name {
        case "engine-idle": try await engineIdle()
        case "engine-tile": await engineTile()
        case "engine-actions": await engineActions()
        case "config-load": try configLoad()
        case "calibrate": calibrate()
        default: fail("unknown scenario \(name)")
        }
    }

    private func engineIdle() async throws {
        let manager = fake.makeManager()
        windows(20)
        await settled(manager)
        try await Task.sleep(for: .seconds(2))
        try await idle(seconds: 10, metric: "engine.idle.cpu")
        record("engine.idle.footprint", Usage.now().footprint)
    }

    private func engineTile() async {
        let before = Usage.now()
        let manager = fake.makeManager()
        windows(50)
        await settled(manager)
        let after = Usage.now()
        record("engine.tile.cpu", after.cpu - before.cpu)
        record("engine.tile.memory", after.footprint - before.footprint)
    }

    private func engineActions() async {
        let manager = fake.makeManager()
        windows(20)
        await settled(manager)
        let actions: [(String, String)] = [
            ("movefocus", "r"), ("swapnext", ""), ("cyclelayout", "next"), ("splitratio", "+0.05"),
            ("workspace", "2"), ("workspace", "1"), ("movetoworkspacesilent", "3"), ("movefocus", "l"),
            ("splitratio", "-0.05"), ("cyclelayout", "prev"), ("swapnext", "prev"), ("workspace", "3"),
            ("movetoworkspace", "1")
        ]
        var writes = 0
        func act(_ step: Int) async {
            let (dispatcher, argument) = actions[step % actions.count]
            manager.dispatch(dispatcher, argument)
            await settled(manager)
            writes += fake.writes.count
            fake.clearWrites()
        }
        for step in 0..<130 { await act(step) }
        let start = Usage.now()
        for step in 0..<390 {
            let before = Usage.now().cpu
            await act(step)
            record("engine.action.cpu", Usage.now().cpu - before)
        }
        record("engine.action.growth", (Usage.now().footprint - start.footprint) * 1024)
        guard writes > 0 else { fail("the actions moved no window") }
        guard RealInput.refusals == 0 else { fail("the actions tried to reach the real input or Desktops") }
        guard !fake.desktopSwitches.isEmpty else { fail("the workspace actions switched no Desktop in the fake") }
    }

    private func configLoad() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-perf-\(getpid())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("catwm.config.ts")
        try Self.config(gaps: 8).write(to: file, atomically: true, encoding: .utf8)
        guard let defaults = UserDefaults(suiteName: "catwm.perf.\(getpid())") else { fail("no defaults suite") }
        let store = ConfigStore(folder: folder, defaults: defaults)
        let before = Usage.now()
        guard store.load().windowMarginSize == 8 else { fail("the config did not load") }
        let after = Usage.now()
        record("config.load.cpu", after.cpu - before.cpu)
        record("config.load.memory", after.footprint - before.footprint)
        for gaps in 9..<29 {
            try Self.config(gaps: gaps).write(to: file, atomically: true, encoding: .utf8)
            let start = Usage.now().cpu
            let reloaded = store.reload()
            record("config.reload.cpu", Usage.now().cpu - start)
            guard reloaded.windowMarginSize == CGFloat(gaps) else { fail("the config did not reload") }
        }
    }

    private func calibrate() {
        for _ in 0..<9 {
            let start = Usage.now().cpu
            var seed: UInt64 = 42
            var values: [UInt64] = []
            var counts: [UInt64: Int] = [:]
            for _ in 0..<300_000 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                values.append(seed >> 33)
                counts[seed % 4096, default: 0] += 1
            }
            values.sort()
            let text = values.prefix(20_000).map(String.init).joined(separator: ",")
            guard counts.count == 4096, !text.isEmpty else { fail("the calibration did not run") }
            record("calibrate.cpu", Usage.now().cpu - start)
        }
    }

    private static func config(gaps: Int) -> String {
        """
        import { catwm } from "./catwm"
        catwm.gaps.size = \(gaps)
        for (const key of ["1", "2", "3", "4", "5", "6", "7", "8", "9"] as const) {
          catwm.bind(["alt"], key, ["workspace", key])
          catwm.bind(["alt", "shift"], key, ["movetoworkspace", key])
        }

        """
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("perf: \(message)\n".utf8))
    exit(1)
}

guard let name = CommandLine.arguments.dropFirst().first else { fail("usage: CatWMPerf <scenario>") }
let scenario = Scenario()
try await scenario.run(name)
let json = try JSONSerialization.data(withJSONObject: scenario.samples, options: [.sortedKeys])
FileHandle.standardOutput.write(json + Data("\n".utf8))
exit(0)
