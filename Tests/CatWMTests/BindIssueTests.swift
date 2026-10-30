@testable import CatWM
import Foundation
import Testing

@MainActor
struct BindIssueTests {
    private func overlaps(_ doc: ConfigDocument, _ index: Int) -> Bool {
        doc.issue(doc.binds[index])?.message.hasPrefix("Overlaps") == true
    }

    @Test func overlapFollowsBindEdits() {
        let doc = ConfigDocument(text: """
        $mod = ALT
        bind = $mod, h, movefocus, l
        bind = $mod, j, movefocus, d

        """)
        #expect(doc.problemCount == 0)
        doc.binds[1].key = "h"
        #expect(overlaps(doc, 0))
        #expect(doc.problemCount == 2)
        doc.binds[1].key = "k"
        #expect(doc.problemCount == 0)
    }

    @Test func overlapFollowsModifierVariable() {
        let doc = ConfigDocument(text: """
        $mod = ALT
        bind = $mod, h, movefocus, l
        bind = CTRL, h, movefocus, d

        """)
        #expect(doc.problemCount == 0)
        doc.modValue = "CTRL"
        #expect(overlaps(doc, 1))
    }

    @Test func nestedModifierAliasesMatchRuntimeAndDetectConflicts() throws {
        let doc = ConfigDocument(text: """
        $primary = CTRL
        $mod = $primary
        bind = $mod, h, movefocus, l
        bind = ALT, h, movefocus, r

        """)
        #expect(doc.config.errors.isEmpty)
        #expect(doc.problemCount == 0)
        let row = try #require(doc.binds.first)
        let combos = try #require(doc.combos(row))
        #expect(combos.map(\.flags) == [UInt(doc.config.bindings[0].mods.rawValue)])
        doc.vars[0].value = "ALT"
        #expect(overlaps(doc, 0))
        #expect(overlaps(doc, 1))
        doc.vars[0].value = "SUPER"
        #expect(doc.problemCount == 0)
        let reparsed = Config.parse(doc.serialize())
        #expect(reparsed.errors.isEmpty)
        #expect(doc.combos(row)?.map(\.flags) == [UInt(reparsed.bindings[0].mods.rawValue)])
    }

    @Test func overlapIsPerSubmapAndCoversRanges() {
        let doc = ConfigDocument(text: """
        $mod = ALT
        bind = $mod, 1..3, workspace, 1..3
        submap = window
        bind = $mod, 2, movefocus, l
        submap = reset

        """)
        #expect(doc.problemCount == 0)
        doc.binds[1].submap = ""
        #expect(overlaps(doc, 1))
        #expect(overlaps(doc, 0))
    }

    @Test func newRowIsCheckedAgainstExistingBinds() {
        let doc = ConfigDocument(text: "$mod = ALT\nbind = $mod, h, movefocus, l\n")
        let candidate = BindRow(mods: "ALT", key: "h", dispatcher: "movefocus", args: "r")
        #expect(doc.issue(candidate)?.message.hasPrefix("Overlaps") == true)
    }

    @Test(arguments: ["CTRL, H|L, movefocus, l|r", "CMD SHIFT, 1..3, workspace, 1..3",
                      "MOD1, esc, submap, reset", ", swipe_left, workspace, r-1"])
    func settingsAndRuntimeInterpretTheSameBind(_ value: String) throws {
        let text = "bind = \(value)\n"
        let config = Config.parse(text)
        let doc = ConfigDocument(text: text)
        let row = try #require(doc.binds.first)
        let combos = try #require(doc.combos(row))
        #expect(config.errors.isEmpty)
        #expect(combos.map(\.code) == config.bindings.map(\.keyCode))
        #expect(combos.map(\.flags) == config.bindings.map { UInt($0.mods.rawValue) })
    }
}
