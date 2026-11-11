@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@MainActor @Suite struct ConfigLegacyTests {
    private func store(_ folder: ConfigFolder) -> ConfigStore {
        let suite = "catwm.test." + UUID().uuidString
        return ConfigStore(folder: folder.url, defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func converted(_ store: ConfigStore) -> Config {
        store.convertLegacyConfig()
        return store.load()
    }

    private func text(_ folder: ConfigFolder, _ name: String = "catwm.config.ts") throws -> String {
        try String(contentsOf: folder.url.appendingPathComponent(name), encoding: .utf8)
    }

    private func old(_ folder: ConfigFolder) throws -> Config {
        let run = ConfigEngine(entry: folder.entry, legacy: true).run()
        var config = Config()
        let value = try #require(run.value?.object)
        let problems = ConfigScript.read(.object(ConfigMigration.renamed(value)), into: &config, file: nil)
        #expect(run.failures.isEmpty && problems.isEmpty)
        return config
    }

    @Test func aRealConfigConvertsToTheSameConfigAndKeepsTheOriginal() throws {
        let folder = try ConfigFolder(["catwm.config.ts": legacyUserConfig])
        defer { folder.remove() }
        let expected = try old(folder)
        let store = store(folder)

        let config = converted(store)

        #expect(store.failures.isEmpty)
        #expect(config.changes(from: expected).isEmpty)
        #expect(expected.bindings.count > 100 && expected.bindings.contains { $0.submap == "window" })
        #expect(config.bindings == expected.bindings)
        #expect(config.layouts == [.bsp, .wide, .floating, .fullscreen])
        #expect(try text(folder, "catwm.config.ts.bak") == legacyUserConfig)
        let script = try text(folder)
        #expect(!script.contains("export default"))
        #expect(script.contains("catwm.motion.duration = 0.12"))
        #expect(script.contains("catwm.bind([\"alt\", \"ctrl\"], \"h\", [\"movefocus\", \"l\"])"))
        #expect(script.contains("catwm.bind([], \"h\", [\"movefocus\", \"l\"], { submap: \"window\" })"))
    }

    @Test func aFileWithAnImportConvertsAndTheOldNamesMove() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": """
            import type { Config } from "./catwm"
            import { base } from "./parts/base"

            export default {
              ...base,
              animation: { duration: 0.3 },
              panelAnimation: "pop",
              modeEffect: "ripple",
              binds: [{ mods: ["alt"], key: "o", run: "sort", repeat: true }],
            } satisfies Config
            """,
            "parts/base.ts": "export const base = { gaps: { size: 14 }, layouts: [\"tall\", \"wide\"] }\n"
        ])
        defer { folder.remove() }
        let expected = try old(folder)
        let store = store(folder)

        let config = converted(store)

        #expect(store.failures.isEmpty)
        #expect(config.changes(from: expected).isEmpty)
        #expect(config.windowMarginSize == 14 && config.panelAnimation == .pop && config.modeEffect == .ripple)
        #expect(config.animationDuration == 0.3)
        #expect(config.bindings.first?.repeats == true)
        let script = try text(folder)
        #expect(script.contains("catwm.motion.panels = \"pop\""))
        #expect(script.contains("catwm.motion.modeEffect = \"ripple\""))
        #expect(!script.contains("animation"))
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("parts/base.ts").path))
    }

    @Test func anExistingBackupIsNeverOverwritten() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "export default { gaps: { size: 3 } }\n",
            "catwm.config.ts.bak": "keep me\n"
        ])
        defer { folder.remove() }

        let config = converted(store(folder))

        #expect(config.windowMarginSize == 3)
        #expect(try text(folder, "catwm.config.ts.bak") == "keep me\n")
        #expect(try text(folder, "catwm.config.ts.2.bak") == "export default { gaps: { size: 3 } }\n")
    }

    @Test func aConversionThatWouldChangeTheResultLeavesTheFileAloneAndSaysWhy() throws {
        let original = "export default { gaps: { size: 5 }, mouse: { swapsWindows: 7 } }\n"
        let folder = try ConfigFolder(["catwm.config.ts": original])
        defer { folder.remove() }
        let store = store(folder)

        _ = converted(store)

        #expect(try text(folder) == original)
        #expect(!FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("catwm.config.ts.bak").path))
        let problem = try #require(store.failures.first)
        #expect(problem.phase == .migrate)
        #expect(problem.message.contains("left the file alone"))
    }

    @Test func aTrialThatGivesAnotherConfigIsNotInstalled() throws {
        let original = "export default { gaps: { size: 5 } }\n"
        let folder = try ConfigFolder(["catwm.config.ts": original])
        defer { folder.remove() }
        let store = store(folder)
        var expected = Config()
        expected.windowMarginSize = 6
        let backup = folder.url.appendingPathComponent("catwm.config.ts.bak")

        let problem = store.install(catwmConfig("catwm.gaps.size = 5"), matching: expected, backup: backup) {
            ConfigDiagnostic(phase: .migrate, message: $0)
        }

        #expect(problem?.message == "the result differs in window-margin-size")
        #expect(try text(folder) == original)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func aNewFormFileIsNotTouched() throws {
        let original = catwmConfig("// export default is gone", "catwm.gaps.size = 9")
        let folder = try ConfigFolder(["catwm.config.ts": original])
        defer { folder.remove() }
        let store = store(folder)

        let config = converted(store)

        #expect(config.windowMarginSize == 9 && store.failures.isEmpty)
        #expect(try text(folder) == original)
        #expect(!FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("catwm.config.ts.bak").path))
    }

    @Test func aLoadAloneNeverConverts() throws {
        let original = "export default { gaps: { size: 3 } }\n"
        let folder = try ConfigFolder(["catwm.config.ts": original])
        defer { folder.remove() }
        let store = store(folder)

        _ = store.load()

        #expect(try text(folder) == original)
        #expect(store.failures.first?.phase == .validate)
    }

    @Test func embeddedModeNeverConverts() throws {
        let original = "export default { gaps: { size: 3 } }\n"
        let folder = try ConfigFolder(["catwm.config.ts": original])
        defer { folder.remove() }
        let defaults = UserDefaults(suiteName: "catwm.test." + UUID().uuidString) ?? .standard
        let store = ConfigStore(folder: folder.url, defaults: defaults, embedded: true)

        _ = store.use(entry: folder.entry)

        #expect(try text(folder) == original)
        #expect(store.failures.first?.phase == .validate)
    }
}
