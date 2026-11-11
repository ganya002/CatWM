@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

func catwmConfig(_ lines: String...) -> String {
    (["import { catwm } from \"./catwm\""] + lines).joined(separator: "\n") + "\n"
}

struct ConfigFolder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-ts-" + UUID().uuidString)

    init(_ files: [String: String]) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (name, text) in files { try write(name, text) }
    }

    var entry: URL { url.appendingPathComponent("catwm.config.ts") }

    func write(_ name: String, _ text: String) throws {
        let file = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    func remove() { Log.attempt("remove test config folder") { try FileManager.default.removeItem(at: url) } }
}

@Suite struct ConfigEngineTests {
    private func run(_ lines: String...) throws -> ConfigEngine.Run {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(lines.joined(separator: "\n"))])
        defer { folder.remove() }
        return ConfigEngine(entry: folder.entry).run()
    }

    @Test func aModuleGraphEvaluatesToTheStore() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": """
            import { catwm } from "./catwm"
            import { gap } from "./gaps"
            interface Local { size: number }
            const local: Local = { size: gap * 2 }
            catwm.gaps.size = local.size
            """,
            "gaps.ts": "export const gap: number = 6\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.isEmpty)
        #expect(run.value?["gaps"]?["size"] == .int(12))
        #expect(run.value?["gaps"]?["smart"] == .bool(true))
        #expect(run.files.map(\.lastPathComponent).sorted() == ["catwm.config.ts", "gaps.ts"])
    }

    @Test func anImportedModuleMayHaveADefaultExport() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": """
            import { catwm } from "./catwm"
            import double from "./double"
            catwm.gaps.size = double(4)
            """,
            "double.ts": "export default function double(value: number) { return value * 2 }\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.isEmpty)
        #expect(run.value?["gaps"]?["size"] == .int(8))
    }

    @Test func anObjectMergesAListOrScalarReplacesAndUndefinedResets() throws {
        let run = try run(
            "catwm.motion = { duration: 0.2 }",
            "catwm.gaps = { size: 4 }",
            "catwm.layouts = [\"bsp\"]",
            "catwm.padding.left = 3",
            "catwm.focus.followsMouse = false",
            "catwm.focus.followsMouse = undefined",
            "catwm.gaps.smart = false",
            "catwm.gaps = { smart: undefined }"
        )

        #expect(run.failures.isEmpty)
        #expect(run.value?["motion"]?["duration"] == .number(0.2))
        #expect(run.value?["motion"]?["curve"] == .string("ease-out"))
        #expect(run.value?["gaps"] == .object(["enabled": .bool(true), "size": .int(4), "smart": .bool(true)]))
        #expect(run.value?["layouts"] == .array([.string("bsp")]))
        #expect(run.value?["padding"]?["left"] == .int(3) && run.value?["padding"]?["right"] == .int(10))
        #expect(run.value?["focus"]?["followsMouse"] == .bool(true))
    }

    @Test func aDefaultListExtendsAndShrinks() throws {
        let run = try run(
            "catwm.layouts.push(\"tall\")",
            "catwm.layouts.remove(\"wide\")",
            "catwm.floating.apps.push(\"com.spotify.client\")"
        )

        #expect(run.value?["layouts"] == .array([.string("bsp"), .string("floating"), .string("fullscreen"),
                                                 .string("tall")]))
        #expect(run.value?["floating"]?["apps"] == .array([.string("com.spotify.client")]))
    }

    @Test func readsReturnTheCurrentValues() throws {
        let run = try run(
            "catwm.gaps.size = 7",
            "catwm.padding = catwm.gaps.size * 2",
            "catwm.floating.listedAppsFloat = catwm.layouts.length === 4"
        )

        #expect(run.failures.isEmpty)
        #expect(run.value?["padding"] == .object(["left": .int(14), "right": .int(14), "top": .int(14),
                                                  "bottom": .int(14)]))
        #expect(run.value?["floating"]?["listedAppsFloat"] == .bool(true))
    }

    @Test func aStyleSetsItsFieldsAndALaterWriteOverridesOneField() throws {
        let run = try run(
            "catwm.motion.curve = \"spring\"",
            "catwm.motion.style = \"relaxed\"",
            "catwm.motion.duration = 0.5",
            "catwm.floating.smallWindows = catwm.motion.style === undefined"
        )

        #expect(run.failures.isEmpty)
        #expect(run.value?["motion"]?["curve"] == .string("ease-in-out"))
        #expect(run.value?["motion"]?["duration"] == .number(0.5))
        #expect(run.value?["motion"]?["enabled"] == .bool(true))
        #expect(run.value?["motion"]?["style"] == nil)
        #expect(run.value?["floating"]?["smallWindows"] == .bool(true))
        #expect(try self.run("catwm.motion.style = \"none\"").value?["motion"]?["enabled"] == .bool(false))
        #expect(try self.run("catwm.motion = { style: \"snappy\", curve: \"linear\" }").value?["motion"]
            == .object(["enabled": .bool(true), "duration": .number(0.12), "curve": .string("linear"),
                        "bounce": .number(0.5), "panels": .string("rise"), "modeEffect": .string("draw")]))
    }

    @Test func aStyleMatchesTheValuesOfItsSettingsTile() {
        for style in MotionStyle.all {
            var config = Config()
            style.apply(to: &config)
            #expect(style.matches(config))
        }
        #expect(MotionStyle.all.map(\.id) == ["none", "snappy", "relaxed"])
    }

    @Test func aSecondFilesWritesSurviveASaveThatChangesOnlyTheFirst() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": catwmConfig("import \"./apps\"", "catwm.gaps.size = 6"),
            "apps.ts": catwmConfig("catwm.floating.apps.push(\"com.apple.calculator\")")
        ])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        #expect(engine.run().value?["floating"]?["apps"] == .array([.string("com.apple.calculator")]))

        try folder.write("catwm.config.ts", catwmConfig("import \"./apps\"", "catwm.gaps.size = 8"))
        let run = engine.run()

        #expect(run.value?["gaps"]?["size"] == .int(8))
        #expect(run.value?["floating"]?["apps"] == .array([.string("com.apple.calculator")]))
        #expect(run.isNew)
        #expect(!engine.run().isNew)
    }

    @Test func aBrokenSaveKeepsTheLastGoodValueAndSaysWhere() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig("catwm.padding = 4")])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        let good = engine.run().value

        try folder.write("catwm.config.ts",
                         "import { catwm } from \"./catwm\"\ncatwm.padding = 4\ncatwm.gaps.size = \n")
        let broken = engine.run()

        #expect(broken.value == good)
        #expect(broken.failures.first?.phase == .transform)
        #expect(broken.failures.first?.line == 4)
        #expect(broken.failures.first?.file == folder.entry.path)

        try folder.write("catwm.config.ts", "const pad = (n: number) => n\nthrow new Error(\"no\")\n")
        let thrown = engine.run()
        #expect(thrown.failures.first?.phase == .evaluate)
        #expect(thrown.failures.first?.line == 2)
        #expect(thrown.failures.first?.message == "Error: no")

        try folder.write("catwm.config.ts", catwmConfig("catwm.padding = 6"))
        #expect(engine.run().value?["padding"]?["top"] == .int(6))
    }

    @Test func aWrongSetterNamesTheLine() throws {
        let typo = try run("catwm.padding = 1", "catwm.gapz = 3")
        let group = try run("catwm.gaps = 4")
        let nested = try run("catwm.gaps = { sise: 4 }")

        #expect(typo.failures.first?.phase == .validate)
        #expect(typo.failures.first?.line == 3)
        #expect(typo.failures.first?.message.hasPrefix("`gapz` is not a CatWM option (catwm has ") == true)
        #expect(group.failures.first?.message == "`gaps` must be an object with enabled, size, smart")
        #expect(nested.failures.first?.message == "`gaps.sise` is not a CatWM option (gaps has enabled, size, smart)")
    }

    @Test func aConfigThatHoldsAFunctionIsRejected() throws {
        let run = try run("catwm.gaps.size = (() => 1) as unknown as number")

        #expect(run.value == nil)
        #expect(run.failures.first?.phase == .validate)
        #expect(run.failures.first?.message == "`gaps.size` is a function. A config holds only data")
    }

    @Test func aWriteAfterTheConfigLoadedIsRefused() throws {
        let late = try run("Promise.resolve().then(() => { catwm.gaps.size = 3 })")
        let tooLate = try run("catwm.bind([\"alt\"], \"a\", () => { catwm.gaps.size = 3 })")

        #expect(late.value == nil)
        #expect(late.failures.first?.phase == .validate)
        #expect(late.failures.first?.line == 2)
        #expect(late.failures.first?.message.hasPrefix("set options while the config loads") == true)
        #expect(tooLate.failures.isEmpty)
    }

    @Test func aDefaultExportSaysHowToConvert() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "export default { gaps: { size: 4 }, layouts: [\"bsp\"] }\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.value == nil)
        #expect(run.failures.first?.phase == .validate)
        #expect(run.failures.first?.file == folder.entry.path)
        #expect(run.failures.first?.message == "`export default` no longer sets the config. Add "
            + "`import { catwm } from \"./catwm\"` and assign each option on it, such as "
            + "catwm.gaps = … and catwm.layouts = …")
    }

    @Test func anOldNameSaysWhatItBecame() throws {
        let animation = try run("catwm.padding = 1", ";(catwm as any).animation = { curve: \"spring\" }")
        #expect(animation.failures.first?.message == "`animation` was renamed to `motion`")
        #expect(try run(";(catwm as any).panelAnimation = \"pop\"").failures.first?.message
            == "`panelAnimation` was renamed to `motion.panels`")
        #expect(try run(";(catwm as any).modeEffect = \"none\"").failures.first?.message
            == "`modeEffect` was renamed to `motion.modeEffect`")
        #expect(try run("catwm.motion = { panels: \"pop\", modeEffect: \"none\" }").value?["motion"]?["panels"]
            == .string("pop"))
    }

    @Test func aModuleCanNotChangeTheExportsOfAnother() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { apps } from \"./apps\"\napps.push(\"B\")\n",
            "apps.ts": "export const apps = [\"A\"]\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.first?.phase == .evaluate)
        #expect(run.failures.first?.line == 2)
        #expect(run.failures.first?.file == folder.entry.path)
    }

    @Test func aFailedRunListsTheFilesItTried() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { size } from \"./shared/gaps\"\nexport const used = size\n",
            "shared/gaps.ts": "export const size = \n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.first?.phase == .transform)
        #expect(run.files.map(\.lastPathComponent).sorted() == ["catwm.config.ts", "gaps.ts"])
    }

    @Test func aMissingImportIsWatchedUntilItExists() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { size } from \"./shared/gaps\"\nexport const used = size\n",
            "shared/other.ts": "export const other = 1\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.first?.phase == .resolve)
        #expect(run.files.map { $0.deletingLastPathComponent().lastPathComponent }.contains("shared"))
    }
}

@Suite struct ConfigKeyFunctionTests {
    private func call(_ engine: ConfigEngine, _ function: Int) async -> ConfigEngine.FunctionRun {
        let window = ConfigEngine.WindowSnapshot(title: "Notes", app: "com.apple.Notes", pid: 42,
                                                 frame: CGRect(x: 10, y: 20, width: 300, height: 200))
        return await withCheckedContinuation { continuation in
            engine.call(function: function, window: window) { continuation.resume(returning: $0) }
        }
    }

    @Test func aKeyFunctionRecordsTheActionsOfTheFocusedWindow() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  const win = catwm.window.focused",
            "  if (win.app === \"com.apple.Notes\" && win.frame.width === 300) win.float()",
            "  win.resize(600, 600)",
            "  win.move(10, 20)",
            "  win.center()",
            "  win.fullscreen()",
            "  win.tile()",
            "  win.moveTo(\"3\")",
            "})",
            "catwm.bind([\"ctrl\"], \"1\", [\"workspace\", \"1\"])"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        let loaded = engine.run()

        #expect(loaded.value?["binds"]?.array?.first?["run"] == .object(["function": .int(0)]))
        #expect(loaded.value?["binds"]?.array?.last?["run"] == .array([.string("workspace"), .string("1")]))
        let result = await call(engine, 0)

        #expect(result.failure == nil)
        #expect(result.actions == [
            RuleAction(dispatcher: "setfloating", arg: ""),
            RuleAction(dispatcher: "resizeactive", arg: "exact 600 600"),
            RuleAction(dispatcher: "moveactive", arg: "exact 10 20"),
            RuleAction(dispatcher: "centerwindow", arg: ""),
            RuleAction(dispatcher: "fullscreen", arg: ""),
            RuleAction(dispatcher: "settiled", arg: ""),
            RuleAction(dispatcher: "movetoworkspacesilent", arg: "3")
        ])
    }

    @Test func aThrowRunsNoActionsAndReportsLikeAConfigError() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => {",
            "  catwm.window.focused.float()",
            "  throw new Error(\"nope\")",
            "})"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.actions.isEmpty)
        #expect(result.failure?.phase == .evaluate)
        #expect(result.failure?.message == "Error: nope")
        #expect(result.failure?.line == 4)
        #expect(await call(engine, 5).failure != nil)
    }

    @Test func aWriteInsideAKeyFunctionIsRefused() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => { catwm.gaps.size = 3 })"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.failure?.phase == .validate)
        #expect(result.failure?.message.hasPrefix("set options while the config loads") == true)
    }

    @Test(.timeLimit(.minutes(1))) func aFunctionThatNeverEndsRunsNoActions() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => { catwm.window.focused.float(); while (true) {} })"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()

        let result = await call(engine, 0)

        #expect(result.actions.isEmpty)
        #expect(result.failure?.message.hasPrefix("the key's function ran longer than 1 s") == true)
    }

    @Test func aFailedSaveKeepsTheFunctionsOfTheLastGoodConfig() async throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => catwm.window.focused.float())"
        )])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run()
        try folder.write("catwm.config.ts", catwmConfig(
            "catwm.bind([\"alt\"], \"c\", () => catwm.window.focused.tile())", "throw new Error(\"broken\")"
        ))
        #expect(engine.run().failures.count == 1)

        #expect(await call(engine, 0).actions == [RuleAction(dispatcher: "setfloating", arg: "")])
    }
}
