@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

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
    @Test func aModuleGraphEvaluatesToItsDefaultExport() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": """
            import type { Config } from "./catwm"
            import { gap } from "./gaps"
            interface Local { size: number }
            const local: Local = { size: gap * 2 }
            export default { gaps: { size: local.size } } satisfies Config
            """,
            "gaps.ts": "export const gap: number = 6\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run(.all)

        #expect(run.failures.isEmpty)
        #expect(run.value == .object(["gaps": .object(["size": .int(12)])]))
        #expect(run.files.map(\.lastPathComponent).sorted() == ["catwm.config.ts", "gaps.ts"])
    }

    @Test func aSaveRerunsOnlyTheChangedModuleAndItsImporters() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": """
            import { gap } from "./gaps"
            import { apps } from "./apps"
            export default { gaps: { size: gap }, floating: { apps } }
            """,
            "gaps.ts": "export const gap = 6\n",
            "apps.ts": "export const apps = [\"com.apple.calculator\"]\n"
        ])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        #expect(engine.run(.all).ran.count == 3)

        try folder.write("gaps.ts", "export const gap = 8\n")
        let run = engine.run(.changed)

        #expect(run.ran.map { URL(fileURLWithPath: $0).lastPathComponent } == ["catwm.config.ts", "gaps.ts"])
        #expect(run.value?["gaps"]?["size"] == .int(8))
        #expect(run.value?["floating"]?["apps"] == .array([.string("com.apple.calculator")]))
        #expect(run.isNew)
        #expect(engine.run(.changed).ran.isEmpty)
    }

    @Test func aBrokenSaveKeepsTheLastGoodValueAndSaysWhere() throws {
        let folder = try ConfigFolder(["catwm.config.ts": "export default { padding: 4 }\n"])
        defer { folder.remove() }
        let engine = ConfigEngine(entry: folder.entry)
        _ = engine.run(.all)

        try folder.write("catwm.config.ts", "export default {\n  padding: 4,\n  gaps: \n}\n")
        let broken = engine.run(.changed)

        #expect(broken.value == .object(["padding": .int(4)]))
        #expect(broken.failures.first?.phase == .transform)
        #expect(broken.failures.first?.line == 4)
        #expect(broken.failures.first?.file == folder.entry.path)

        try folder.write("catwm.config.ts", "const pad = (n: number) => n\nthrow new Error(\"no\")\n")
        let thrown = engine.run(.changed)
        #expect(thrown.failures.first?.phase == .evaluate)
        #expect(thrown.failures.first?.line == 2)
        #expect(thrown.failures.first?.message == "Error: no")

        try folder.write("catwm.config.ts", "export default { padding: 6 }\n")
        #expect(engine.run(.changed).value == .object(["padding": .int(6)]))
    }

    @Test func aConfigThatHoldsAFunctionIsRejected() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "export default { binds: [{ key: \"a\", run: () => 1 }] }\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run(.all)

        #expect(run.value == nil)
        #expect(run.failures.first?.phase == .validate)
        #expect(run.failures.first?.message == "`binds[0].run` is a function. A config holds only data")
    }

    @Test func aModuleCanNotChangeTheExportsOfAnother() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { apps } from \"./apps\"\napps.push(\"B\")\n"
                + "export default { floating: { apps } }\n",
            "apps.ts": "export const apps = [\"A\"]\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run(.all)

        #expect(run.failures.first?.phase == .evaluate)
        #expect(run.failures.first?.line == 2)
        #expect(run.failures.first?.file == folder.entry.path)
    }

    @Test func aFailedRunListsTheFilesItTried() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { size } from \"./shared/gaps\"\nexport default { gaps: { size } }\n",
            "shared/gaps.ts": "export const size = \n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run(.all)

        #expect(run.failures.first?.phase == .transform)
        #expect(run.files.map(\.lastPathComponent).sorted() == ["catwm.config.ts", "gaps.ts"])
    }

    @Test func aMissingImportIsWatchedUntilItExists() throws {
        let folder = try ConfigFolder([
            "catwm.config.ts": "import { size } from \"./shared/gaps\"\nexport default { gaps: { size } }\n",
            "shared/other.ts": "export const other = 1\n"
        ])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run(.all)

        #expect(run.failures.first?.phase == .resolve)
        #expect(run.files.map { $0.deletingLastPathComponent().lastPathComponent }.contains("shared"))
    }
}
