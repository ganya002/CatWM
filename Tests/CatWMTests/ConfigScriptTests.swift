@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct ConfigScriptTests {
    private func read(_ lines: String...) throws -> (Config, [ConfigDiagnostic]) {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(lines.joined(separator: "\n"))])
        defer { folder.remove() }
        let run = ConfigEngine(entry: folder.entry).run()
        let value = try #require(run.value, "\(run.failures.map(\.text))")
        var config = Config()
        let diagnostics = ConfigScript.read(value, into: &config, file: folder.entry.path)
        return (config, diagnostics)
    }

    @Test func settersSetOptionsBindsAndSubmaps() throws {
        let (config, diagnostics) = try read("""
        const mod = "alt"
        catwm.mod = mod
        catwm.layouts = ["tall", "bsp", "tall"]
        catwm.gaps = { size: 14, smart: false }
        catwm.padding = 6
        catwm.floating.apps = ["com.apple.calculator"]
        catwm.floating.listedAppsFloat = false
        catwm.motion = { curve: "spring", duration: 0.2 }
        catwm.features.presentation.hud = false
        for (const key of ["1", "2", "3"] as const) catwm.bind(["ctrl"], key, ["workspace", key])
        catwm.bind([mod, "shift"], "tab", ["switcher", "prev"])
        catwm.bind(["cmd"], "capslock", ["submap", "window"])
        catwm.bind([], "h", ["movefocus", "l"], { submap: "window", repeat: true })
        catwm.bind([], "escape", ["submap", "reset"], { submap: "window" })
        catwm.bind([], "o", "sort", { submap: "window" })
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

    @Test func aKeyFunctionBecomesABindWithAFunctionNumber() throws {
        let (config, diagnostics) = try read("""
        catwm.bind(["alt"], "a", "sort")
        catwm.bind(["alt"], "c", () => catwm.window.focused.float())
        """)

        #expect(diagnostics.isEmpty)
        #expect(config.bindings.map(\.function) == [nil, 0])
        #expect(config.bindings.last?.dispatcher == "function")
        #expect(ConfigScript.json(config.bindings[1])["run"] == .object(["function": .int(0)]))
    }

    @Test(arguments: [
        ("catwm.gaps = { size: \"4\" as any }", "`gaps.size` must be a number"),
        ("catwm.layouts = [\"tal\" as any]", "`layouts` has an unknown layout `tal`"),
        ("catwm.bind([], \"1..0\" as any, \"sort\")",
         "`binds[0].key` is an unknown key `1..0`. Write one bind for each key, for example with map()"),
        ("catwm.bind([\"super\" as any], \"a\", \"sort\")",
         "`binds[0].mods` has an unknown modifier `super` (cmd, alt, ctrl, shift)"),
        ("catwm.bind([], \"a\", [\"sortt\" as any])", "`binds[0].run` is an unknown action `sortt`"),
        ("catwm.features.windows.tabGroups = false",
         "`features.presentation.tabStrips` needs `features.windows.tabGroups`, which is off"),
        ("catwm.motion.curve = \"wobbly\" as any",
         "`motion.curve`: unknown animation curve `wobbly` (ease-out, ease-in-out, linear, spring, bounce, "
            + "overshoot or cubic-bezier(x1, y1, x2, y2))")
    ])
    func aWrongValueSaysWhatIsWrong(_ source: String, _ message: String) throws {
        let (_, diagnostics) = try read(source)
        #expect(diagnostics.map(\.message) == [message])
        #expect(diagnostics.first?.phase == .validate)
    }

    @Test func anOldNameInTheValueSaysWhatItBecame() {
        var config = Config()
        let diagnostics = ConfigScript.read(.object(["animation": .object(["curve": .string("spring")]),
                                                     "panelAnimation": .string("pop")]),
                                            into: &config, file: nil)

        #expect(diagnostics.map(\.message) == ["`animation` was renamed to `motion`",
                                               "`panelAnimation` was renamed to `motion.panels`"])
    }

    @Test func anOldOverridesFileKeepsWorking() {
        let renamed = ConfigScript.renamingOverrides([
            "animation": .object(["duration": .number(0.3)]), "modeEffect": .string("none"),
            "gaps": .object(["size": .int(4)])
        ])

        #expect(renamed == [
            "motion": .object(["duration": .number(0.3), "modeEffect": .string("none")]),
            "gaps": .object(["size": .int(4)])
        ])
    }

    @Test func windowRulesAreReadAsData() throws {
        let (config, diagnostics) = try read("""
        catwm.windows({ app: "com.apple.Safari", title: /settings/i, floating: false }, (win) => {
          win.float()
          win.size = { width: 600, height: 500 }
          win.position = "center"
          win.workspace = "3"
        })
        catwm.windows({ app: "com.apple.finder*", pid: 9 }, (win) => {
          win.position = { x: 1, y: 2 }
          win.display = "external"
          win.tile()
          win.fullscreen()
        })
        """)

        #expect(diagnostics.isEmpty)
        #expect(config.windowRules.count == 2)
        let first = config.windowRules[0]
        #expect(first.actions == [
            RuleAction(dispatcher: "setfloating", arg: ""),
            RuleAction(dispatcher: "resizeactive", arg: "exact 600 500"),
            RuleAction(dispatcher: "centerwindow", arg: ""), RuleAction(dispatcher: "movetoworkspacesilent", arg: "3")
        ])
        #expect(config.windowRules[1].actions.map(\.dispatcher)
            == ["moveactive", "movewindowtomonitor", "settiled", "fullscreen"])
        let safari: Facts = [.app: .string("com.apple.Safari"), .title: .string("Display SETTINGS"),
                             .floating: .bool(false)]
        #expect(first.when.holds(safari))
        #expect(!first.when.holds(safari.merging([.title: .string("Inbox")]) { $1 }))
        #expect(!first.when.holds(safari.merging([.floating: .bool(true)]) { $1 }))
        #expect(config.windowRules[1].when.holds([.app: .string("com.apple.finder.Sync"), .pid: .int(9)]))
        #expect(!config.windowRules[1].when.holds([.app: .string("com.apple.finder.Sync"), .pid: .int(8)]))
    }

    @Test func workspaceRulesRecordTheWritesOfTheirCallback() throws {
        let (config, diagnostics) = try read("""
        catwm.workspaces({ sameApp: { atLeast: 2 }, layout: "bsp", focused: true }, () => {
          catwm.motion.style = "relaxed"
          catwm.gaps.size = catwm.gaps.size + 2
          catwm.layouts.push("tall")
        })
        catwm.gaps.size = 3
        """)

        #expect(diagnostics.isEmpty)
        #expect(config.windowMarginSize == 3 && config.animationCurve == .easeOut)
        #expect(config.workspaceRules.count == 1)
        let rule = config.workspaceRules[0]
        #expect(rule.set == [
            "motion.enabled": .bool(true), "motion.curve": .string("ease-in-out"), "motion.duration": .number(0.35),
            "gaps.size": .int(12), "layouts": .array(["bsp", "wide", "floating", "fullscreen", "tall"].map(JSON.string))
        ])
        let facts: Facts = [.sameApp: .int(2), .layout: .string("bsp"), .focused: .bool(true)]
        #expect(rule.when.holds(facts))
        #expect(!rule.when.holds(facts.merging([.sameApp: .int(1)]) { $1 }))
        #expect(!rule.when.holds(facts.merging([.focused: .bool(false)]) { $1 }))
    }

    @Test func aWorkspaceRuleMayOnlySetScopedOptions() throws {
        let (config, diagnostics) = try read("""
        catwm.workspaces({ windows: 3 }, () => {
          catwm.mouse.splitHandle = false
          catwm.gaps.size = 5
        })
        """)

        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.hasPrefix("catwm.workspaces rule 1 can't set `mouse.splitHandle`. "
            + "A workspace rule can set only focusDim.blur, ") == true, "\(diagnostics.map(\.message))")
        #expect(config.workspaceRules.isEmpty)
        #expect(ConfigScript.isScoped("layouts") && ConfigScript.isScoped("focusDim.blur"))
        #expect(!ConfigScript.isScoped("mouse.splitHandle") && !ConfigScript.isScoped("mod"))
    }

    @Test func aRuleThatCanNotConvertIsRejected() throws {
        let (config, diagnostics) = try read("""
        catwm.windows({ title: /[^]/ }, (win) => win.float())
        catwm.windows({ title: /ok/ }, (win) => win.float())
        catwm.windows({ pid: "no" as any, nope: 1 } as any, (win) => win.float())
        """)

        #expect(diagnostics.count == 3)
        #expect(diagnostics.first?.message.hasPrefix("catwm.windows rule 1 match `title` is the regular expression "
            + "/[^]/, which CatWM can't match") == true)
        #expect(diagnostics.dropFirst().map(\.message).contains {
            $0.contains("unknown match field `nope`") || $0.contains("match `pid` must be a number")
        })
        #expect(config.windowRules.count == 1)
    }

    @Test func aRulesChangeIsAChange() throws {
        let (first, _) = try read("catwm.windows({ title: /a/ }, (win) => win.float())")
        let (same, _) = try read("catwm.windows({ title: /a/ }, (win) => win.float())")
        let (other, _) = try read("catwm.windows({ title: /b/ }, (win) => win.float())")
        let (workspace, _) = try read("catwm.workspaces({ windows: 2 }, () => { catwm.gaps.size = 1 })")

        #expect(same.changes(from: first).isEmpty)
        #expect(other.changes(from: first) == ["windowRules"])
        #expect(workspace.changes(from: first).contains("workspaceRules"))
    }

    @Test func aBindCanNotBeDeclaredInsideARule() throws {
        let folder = try ConfigFolder(["catwm.config.ts": catwmConfig(
            "catwm.workspaces({}, () => { catwm.bind([], \"a\", \"sort\") })"
        )])
        defer { folder.remove() }

        let run = ConfigEngine(entry: folder.entry).run()

        #expect(run.failures.first?.message == "catwm.bind can't be used inside catwm.workspaces")
        #expect(run.failures.first?.line == 2)
    }
}
