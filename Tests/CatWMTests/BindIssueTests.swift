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
}
