@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@MainActor @Suite struct ConfigStoreTests {
    private func store(_ folder: ConfigFolder) -> ConfigStore {
        let suite = "catwm.test." + UUID().uuidString
        return ConfigStore(folder: folder.url, defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func overrides(_ folder: ConfigFolder) -> JSON? {
        (try? Data(contentsOf: folder.url.appendingPathComponent(ConfigStore.overridesName))).flatMap(JSON.parse)
    }

    @Test func overridesWinOverTheTypeScriptConfigUntilReset() throws {
        let folder = try ConfigFolder(["catwm.config.ts": "export default { gaps: { size: 8 } }\n"])
        defer { folder.remove() }
        let store = store(folder)
        #expect(store.load().windowMarginSize == 8)

        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "12")
        #expect(store.reload(.changed).windowMarginSize == 12)
        #expect(overrides(folder) == .object(["gaps": .object(["size": .int(12)])]))
        #expect(store.overriddenPaths == ["gaps.size"])

        try folder.write("catwm.config.ts", "export default { gaps: { size: 10 } }\n")
        #expect(store.reload(.changed).windowMarginSize == 12)
        #expect(store.base.windowMarginSize == 10)

        try store.resetOverride("gaps.size")
        #expect(store.reload(.changed).windowMarginSize == 10)
        #expect(overrides(folder) == nil)
    }

    @Test func aBrokenOverridesFileKeepsTheLastGoodConfig() throws {
        let folder = try ConfigFolder(["catwm.config.ts": "export default { gaps: { size: 8 } }\n"])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "20")
        #expect(store.reload(.changed).windowMarginSize == 20)

        try folder.write(ConfigStore.overridesName, "{ \"gaps\": ")
        let kept = store.reload(.changed)

        #expect(kept.windowMarginSize == 20)
        #expect(store.failures.first?.file == folder.url.appendingPathComponent(ConfigStore.overridesName).path)
        try folder.write(ConfigStore.overridesName, "{ \"gaps\": { \"size\": 12 } }")
        #expect(store.reload(.changed).windowMarginSize == 12)
        #expect(store.failures.isEmpty)
    }

    @Test func settingsKeepsDollarSignsInBindArguments() throws {
        let folder = try ConfigFolder(["catwm.config.ts": """
        export default { binds: [{ mods: ["alt"], key: "t", run: ["exec", "echo $mod $HOME"] }] }
        """])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()

        let edited = ConfigText(store.settingsText).config

        #expect(edited.bindings.first?.arg == "echo $mod $HOME")
        #expect(edited.changes(from: store.base).isEmpty)
    }

    @Test func aSettingsSaveKeepsValuesTheSettingsTextCanNotHold() throws {
        let folder = try ConfigFolder(["catwm.config.ts": """
        export default {
          mod: [],
          binds: [{ mods: ["alt"], key: "t", run: ["exec", "echo first\\necho second"] }],
        }
        """])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        let copy = store.settingsCopy
        var edited = copy.shown
        edited.windowMarginSize = 30

        try store.save(settings: edited, from: copy)

        #expect(overrides(folder) == .object(["gaps": .object(["size": .int(30)])]))
        let current = store.reload(.changed)
        #expect(current.mainMod.isEmpty)
        #expect(current.bindings.first?.arg == "echo first\necho second")
    }

    @Test func anUnreadableOverridesFileKeepsTheLastGoodConfig() throws {
        let folder = try ConfigFolder(["catwm.config.ts": "export default { gaps: { size: 8 } }\n"])
        let file = folder.url.appendingPathComponent(ConfigStore.overridesName)
        defer {
            Log.attempt("unlock overrides") {
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            }
            folder.remove()
        }
        let store = store(folder)
        _ = store.load()
        try store.set(option: ConfigOption.at(\Config.windowMarginSize), "20")
        #expect(store.reload(.changed).windowMarginSize == 20)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.path)

        #expect(store.reload(.changed).windowMarginSize == 20)
        #expect(store.failures.first?.message == "CatWM can't read this file")
    }

    @Test(.timeLimit(.minutes(1))) func aConfigThatNeverFinishesDoesNotHoldUpCatWM() throws {
        let folder = try ConfigFolder(["catwm.config.ts": "export default { gaps: { size: 8 } }\n"])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()

        try folder.write("catwm.config.ts", "while (true) {}\nexport default {}\n")
        let started = Date()
        let kept = store.reload(.all)

        #expect(Date().timeIntervalSince(started) < ConfigStore.timeLimit)
        #expect(kept.windowMarginSize == 8)
        let message = store.failures.first?.message ?? ""
        #expect(message.hasPrefix("the config ran longer than 1 s, so CatWM stopped it"))
        try folder.write("catwm.config.ts", "export default { gaps: { size: \"wide\" } }\n")
        #expect(store.reload(.changed).windowMarginSize == 8)
        try folder.write("catwm.config.ts", "export default { gaps: { size: 12 } }\n")
        #expect(store.reload(.changed).windowMarginSize == 12)
    }

    @Test func aSettingsSaveFromAnOlderCopyKeepsBindsTheFileMoved() throws {
        let folder = try ConfigFolder(["catwm.config.ts": """
        export default { binds: [{ mods: ["alt"], key: "a", run: "sort" }, { mods: ["alt"], key: "b", run: "retile" }] }
        """])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        let copy = store.settingsCopy
        var edited = copy.shown
        edited.bindings[0] = KeyBinding(keyCode: 8, mods: .maskAlternate, dispatcher: "sort", arg: "")
        try folder.write("catwm.config.ts", """
        export default { binds: [{ mods: ["alt"], key: "b", run: "retile" }, { mods: ["alt"], key: "a", run: "sort" }] }
        """)
        _ = store.reload(.changed)

        try store.save(settings: edited, from: copy)

        let binds = store.reload(.changed).bindings
        #expect(binds.map(\.keyCode) == [8, 11])
        #expect(binds.map(\.dispatcher) == ["sort", "retile"])
    }

    @Test func aSettingsSaveWritesOnlyWhatDiffersFromTheTypeScriptConfig() throws {
        let folder = try ConfigFolder(["catwm.config.ts": """
        export default {
          gaps: { size: 8 },
          binds: [{ mods: ["alt"], key: "o", run: "sort" }],
        }
        """])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        let copy = store.settingsCopy
        var edited = copy.shown
        #expect(edited.changes(from: store.current).isEmpty)

        edited.animate = false
        edited.bindings[0] = KeyBinding(keyCode: 31, mods: [.maskAlternate, .maskShift], dispatcher: "sort", arg: "")
        try store.save(settings: edited, from: copy)

        #expect(overrides(folder) == .object([
            "animation": .object(["enabled": .bool(false)]),
            "binds": .array([.object(["mods": .array([.string("alt"), .string("shift")]), "key": .string("o"),
                                      "run": .string("sort")])]),
            "submaps": .object([:])
        ]))
        let current = store.reload(.changed)
        #expect(!current.animate && current.windowMarginSize == 8)
        #expect(current.bindings.first?.mods == [.maskAlternate, .maskShift])
        #expect(store.base.bindings.first?.mods == .maskAlternate)
    }

    @Test func theFirstLaunchConvertsTheConfFileOnceAndKeepsItAsABackup() throws {
        let conf = "$mod = CTRL\nwindow-margin-size = 4\nbind = $mod, o, sort\n"
        let folder = try ConfigFolder(["catwm.conf": conf])
        defer { folder.remove() }

        let config = store(folder).load()

        #expect(config.changes(from: Config.parse(conf)).isEmpty)
        #expect(try String(contentsOf: folder.url.appendingPathComponent("catwm.conf"), encoding: .utf8) == conf)
        let script = try String(contentsOf: folder.entry, encoding: .utf8)
        #expect(script.contains("{ mods: [mod], key: \"o\", run: \"sort\" },"))
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("catwm.d.ts").path))
        #expect(FileManager.default.fileExists(atPath: folder.url.appendingPathComponent("tsconfig.json").path))

        try folder.write("catwm.conf", "window-margin-size = 40\n")
        #expect(store(folder).load().windowMarginSize == 4)
    }

    @Test func aConfThatCanNotBeConvertedStaysInUseAndSaysWhy() throws {
        let conf = "window-margin-size = 4\n"
        let folder = try ConfigFolder(["catwm.conf": conf])
        defer {
            Log.attempt("unlock test folder") {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path)
            }
            folder.remove()
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.url.path)
        let store = store(folder)

        let config = store.load()

        #expect(store.source == .conf)
        #expect(config.windowMarginSize == 4)
        #expect(store.failures.first?.phase == .migrate)
        #expect(config.errors.first?.hasPrefix("catwm.conf: CatWM couldn't convert catwm.conf") == true)
        #expect(!FileManager.default.fileExists(atPath: folder.entry.path))
    }

    @Test(.timeLimit(.minutes(1))) func aSaveInTheModuleGraphAppliesWithoutAReload() async throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { size } from \"./parts/gaps\"\nexport default { gaps: { size } }\n",
            "parts/gaps.ts": "export const size = 8\n"
        ])
        defer { folder.remove() }
        let store = store(folder)
        _ = store.load()
        var applied: [Config] = []
        store.watch { applied.append($0) }

        try folder.write("parts/gaps.ts", "export const size = 16\n")
        #expect(await poll(30) { applied.last?.windowMarginSize == 16 })

        try folder.write("parts/gaps.ts", "export const size = \n")
        #expect(await poll(30) { !store.failures.isEmpty })
        #expect(applied.last?.windowMarginSize == 16)
        #expect(applied.last?.errors.first?.hasPrefix("gaps.ts:2:") == true)
    }
}
