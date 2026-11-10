@testable import CatWM
import Foundation
import Testing

@Suite struct ConfigMigrationTests {
    private struct Migrated {
        var source = ""
        var config = Config()
        var diagnostics: [ConfigDiagnostic] = []
    }

    private func migrated(_ conf: String) throws -> Migrated {
        var result = Migrated(source: ConfigMigration.typescript(from: conf, header: ["// test"]))
        let folder = try ConfigFolder(["catwm.config.ts": result.source])
        defer { folder.remove() }
        let run = ConfigEngine(entry: folder.entry).run(.all)
        result.diagnostics = run.failures
        if let value = run.value { result.diagnostics += ConfigScript.read(value, into: &result.config, file: nil) }
        return result
    }

    @Test(arguments: [defaultText, wasdText])
    func theStockConfigsMigrateToTheSameConfig(_ conf: String) throws {
        let result = try migrated(conf)
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.text))\n\(result.source)")
        #expect(result.config.changes(from: Config.parse(conf)).isEmpty)
    }

    @Test func variablesSubmapsAliasesRangesAndCommentsCarryOver() throws {
        let conf = """
        # my main key
        $mod = SUPER
        $term = Alacritty
        general {
            gaps_in = 3 # half the gap
        }
        smart-gaps = false
        animations {
            enabled = false
        }
        layouts = tall, wide
        bind = $mod SHIFT, 1..3, movetoworkspace, 1..3
        bind = $mod, t, exec, open -a $term
        binde = $mod, l, splitratio, +0.05
        frobnicate = 7
        submap = resize
        bind = , escape, submap, reset
        submap = reset
        """
        let result = try migrated(conf)

        #expect(result.diagnostics.isEmpty)
        #expect(result.config.changes(from: Config.parse(conf)).isEmpty)
        #expect(result.source.contains("const mod = \"cmd\""))
        #expect(result.source.contains("{ mods: [mod, \"shift\"], key: \"3\", run: [\"movetoworkspace\", \"3\"] },"))
        #expect(result.source.contains("run: [\"exec\", `open -a ${term}`]"))
        #expect(result.source.contains("    // half the gap\n    size: 6,"))
        #expect(result.source.contains("smart: false"))
        #expect(result.source.contains("// my main key\nconst mod"))
        let note = "// catwm migration: not converted (unknown option `frobnicate`): frobnicate = 7"
        #expect(result.source.contains(note))
        #expect(result.source.contains("  submaps: {\n    resize: ["))
        #expect(result.source.contains("      { key: \"escape\", run: [\"submap\", \"reset\"] },"))
    }

    @Test func aReassignedVariableKeepsTheValueOfEachBind() throws {
        let conf = """
        $app = Safari
        bind = ALT, s, exec, open -a $app
        $app = Mail
        bind = ALT, m, exec, open -a $app
        """
        let result = try migrated(conf)

        #expect(result.diagnostics.isEmpty)
        #expect(result.config.changes(from: Config.parse(conf)).isEmpty)
        #expect(result.source.contains("const app = \"Safari\"\nconst app2 = \"Mail\""))
    }
}
