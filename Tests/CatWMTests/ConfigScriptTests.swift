@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct ConfigScriptTests {
    private func read(_ source: String) throws -> (Config, [ConfigDiagnostic]) {
        let folder = try ConfigFolder(["catwm.config.ts": source])
        defer { folder.remove() }
        let value = try #require(ConfigEngine(entry: folder.entry).run(.all).value)
        var config = Config()
        let diagnostics = ConfigScript.read(value, into: &config, file: folder.entry.path)
        return (config, diagnostics)
    }

    @Test func aTypedObjectSetsOptionsBindsAndSubmaps() throws {
        let (config, diagnostics) = try read("""
        const mod = "alt"
        const workspaces = ["1", "2", "3"].map((key) => ({ mods: ["ctrl"], key, run: ["workspace", key] }))
        export default {
          mod,
          layouts: ["tall", "bsp", "tall"],
          gaps: { size: 14, smart: false },
          padding: 6,
          floating: { apps: ["com.apple.calculator"], listedAppsFloat: false },
          animation: { curve: "spring", duration: 0.2 },
          features: { presentation: { hud: false } },
          binds: [
            ...workspaces,
            { mods: [mod, "shift"], key: "tab", run: ["switcher", "prev"] },
            { mods: ["cmd"], key: "capslock", run: ["submap", "window"] },
          ],
          submaps: {
            window: [
              { key: "h", run: ["movefocus", "l"], repeat: true },
              { key: "escape", run: ["submap", "reset"] },
              { key: "o", run: "sort" },
            ],
          },
        }
        """)

        #expect(diagnostics.isEmpty)
        #expect(config.mainMod == .maskAlternate)
        #expect(config.layouts == [.tall, .bsp])
        #expect(config.windowMarginSize == 14 && !config.smartWindowMargins && config.windowMargins)
        #expect([config.paddingLeft, config.paddingRight, config.paddingTop, config.paddingBottom] == [6, 6, 6, 6])
        #expect(config.floating == ["com.apple.calculator"] && !config.floatingIsDenylist)
        #expect(config.animationCurve == .spring && config.animationDuration == 0.2)
        #expect(!config.features.contains(.hud) && config.features.contains(.keys))
        let global = config.bindings.filter(\.submap.isEmpty)
        #expect(global.map(\.keyCode) == [18, 19, 20, 48, 57])
        #expect(global.map(\.arg) == ["1", "2", "3", "prev", "window"])
        #expect(global[3].mods == [.maskAlternate, .maskShift])
        let window = config.bindings.filter { $0.submap == "window" }
        #expect(window.map(\.dispatcher) == ["movefocus", "submap", "sort"])
        #expect(window.map(\.repeats) == [true, false, false])
        #expect(config.bindRows.map(\.mods).prefix(4) == ["CTRL", "CTRL", "CTRL", "ALT SHIFT"])
    }

    @Test(arguments: [
        ("export default { gaps: { sise: 4 } }", "`gaps.sise` is not a CatWM option (gaps has enabled, size, smart)"),
        ("export default { gaps: { size: \"4\" } }", "`gaps.size` must be a number"),
        ("export default { layouts: [\"tal\"] }", "`layouts` has an unknown layout `tal`"),
        ("export default { binds: [{ key: \"1..0\", run: \"sort\" }] }",
         "`binds[0].key` is an unknown key `1..0`. Write one bind for each key, for example with map()"),
        ("export default { binds: [{ mods: [\"super\"], key: \"a\", run: \"sort\" }] }",
         "`binds[0].mods` has an unknown modifier `super` (cmd, alt, ctrl, shift)"),
        ("export default { binds: [{ key: \"a\", run: [\"sortt\"] }] }", "`binds[0].run` is an unknown action `sortt`"),
        ("export default { features: { windows: { tabGroups: false } } }",
         "`features.presentation.tabStrips` needs `features.windows.tabGroups`, which is off"),
        ("export default { animation: { curve: \"wobbly\" } }",
         "`animation.curve`: unknown animation curve `wobbly` (ease-out, ease-in-out, linear, spring, bounce, "
            + "overshoot or cubic-bezier(x1, y1, x2, y2))")
    ])
    func aWrongValueSaysWhatIsWrong(_ source: String, _ message: String) throws {
        let (_, diagnostics) = try read(source)
        #expect(diagnostics.map(\.message) == [message])
        #expect(diagnostics.first?.phase == .validate)
    }
}
