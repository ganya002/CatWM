@testable import CatWM
import Testing

@Suite struct ConfigTextTests {
    @Test func openingAndSavingKeepsTextExactly() {
        let text = "# personal config\r\n\r\nwindow-margins = off # keep me\r\nunknown = value\r\n"
        #expect(ConfigDocument(text: text).serialize() == text)
    }

    @Test func settingsEditsKeepCommentsAndOrder() {
        let text = "# before\nwindow-margins = true # explanation\nunknown = keep\n# after\n"
        let doc = ConfigDocument(text: text)
        doc.config.windowMargins = false
        let saved = doc.serialize()
        #expect(saved == "# before\nwindow-margins = false # explanation\nunknown = keep\n# after\n")
        #expect(!Config.parse(saved).windowMargins)
    }

    @Test func variableExpansionAgreesWithSettingsAfterAnEdit() {
        let text = "$gap = 12\n$gap = 24\nwindow-margin-size = $gap\n"
        let doc = ConfigDocument(text: text)
        #expect(doc.config.windowMarginSize == 24)
        doc.vars[0].value = "30"
        let saved = doc.serialize()
        #expect(saved == "$gap = 12\n$gap = 30\nwindow-margin-size = $gap\n")
        #expect(Config.parse(saved).windowMarginSize == 30)
    }

    @Test func editingABindKeepsItsSubmapAndComment() {
        let text = "submap = window\nbind = , H, movefocus, l # left\nsubmap = reset\n"
        let doc = ConfigDocument(text: text)
        doc.binds[0].key = "J"
        let saved = doc.serialize()
        #expect(saved.contains("bind = , J, movefocus, l # left"))
        #expect(Config.parse(saved).bindings.first?.submap == "window")
    }

    @Test func movedAndNewBindsUseTheirOwnSubmap() {
        let doc = ConfigDocument(text: "submap = window\nbind = , H, movefocus, l\n")
        doc.binds[0].submap = "other"
        doc.binds.append(BindRow(mods: "CTRL", key: "J", dispatcher: "movefocus", args: "d"))
        let saved = Config.parse(doc.serialize())
        #expect(saved.errors.isEmpty)
        #expect(saved.bindings.map(\.submap) == ["other", ""])
    }

    @Test func blockEditsKeepTheirContext() {
        let doc = ConfigDocument(text: "animations {\n  enabled = true # motion\n}\n")
        doc.config.animate = false
        let saved = doc.serialize()
        #expect(saved == "animations {\n  enabled = false # motion\n}\n")
        #expect(!Config.parse(saved).animate)
    }

    @Test func duplicateAliasesAndHashesRoundTrip() {
        let text = "keyboard-help-key = ?\nkeyboard_help_key = ? # key\n"
        let saved = ConfigText(text).setting(option: "keyboard-help-key", to: "#")
        #expect(saved == "keyboard-help-key = ?\nkeyboard-help-key = ## # key\n")
        #expect(Config.parse(saved).keyboardHelpKey == "#")
    }

    @Test func editingOneSideKeepsCompositePadding() {
        let doc = ConfigDocument(text: "gaps_out = 20\n")
        doc.config.paddingLeft = 40
        let parsed = Config.parse(doc.serialize())
        #expect(parsed.paddingLeft == 40)
        #expect(parsed.paddingRight == 20)
        #expect(parsed.paddingTop == 20)
    }
}

@Test func aLaterCompositePaddingDoesNotHideAnOptionWrite() {
    let source = ConfigText("screen-padding-left = 10\ngaps_out = 20\n")
    let saved = Config.parse(source.setting(option: "screen-padding-left", to: "40"))
    #expect(saved.paddingLeft == 40)
    #expect(saved.paddingRight == 20)
}

@Test func exportingKeyboardSettingsIncludesIndentedBinds() {
    let doc = ConfigDocument(text: "$mod = CTRL\nsubmap = window\n  bind = , H, movefocus, l\nsubmap = reset\n")
    let parsed = Config.parse(doc.keyboardText())
    #expect(parsed.errors.isEmpty)
    #expect(parsed.bindings.count == 1)
    #expect(parsed.bindings.first?.submap == "window")
}

@Test func deletingABindKeepsItsCommentAndUnknownNeighbours() {
    let doc = ConfigDocument(text: "bind = CTRL, H, movefocus, l # left\nunknown = keep\n")
    doc.binds.removeAll()
    let saved = doc.serialize()
    #expect(saved == "# left\nunknown = keep\n")
    #expect(Config.parse(saved).bindings.isEmpty)
}

@Test func anExportedSettingsSnapshotEscapesHashes() {
    let doc = ConfigDocument(text: "keyboard-help-key = ##\nfloating = com.example.##app\n")
    let snapshot = Config.parse(doc.serialize(includeKeyboard: false, includeAnimation: false))
    #expect(snapshot.keyboardHelpKey == "#")
    #expect(snapshot.floating == ["com.example.#app"])
}

@Test func editingAHashEscapesItExactlyOnce() {
    let doc = ConfigDocument(text: "keyboard-help-key = ? # toggle help\n")
    doc.config.keyboardHelpKey = "#"
    let text = doc.serialize()
    #expect(text == "keyboard-help-key = ## # toggle help\n")
    #expect(Config.parse(text).keyboardHelpKey == "#")
}

@Test(arguments: [
    "$mod = CTRL\nbind = $mod, J, movefocus, d\n",
    "$gap = 8\n$mod = CTRL\nbind = $mod, J, movefocus, d\n"
])
func aKeyboardImportKeepsSettingsThatUsedReplacedVariables(_ keyboard: String) {
    let doc = ConfigDocument(text: """
    $gap = 24
    window-margin-size = $gap # spacing
    $mod = ALT
    bind = $mod, H, movefocus, l
    """)
    doc.applyKeyboard(keyboard)
    let saved = doc.serialize()
    let parsed = Config.parse(saved)
    #expect(parsed.errors.isEmpty)
    #expect(parsed.windowMarginSize == 24)
    #expect(saved.contains("window-margin-size = 24 # spacing"))
    #expect(parsed.bindings.count == 1)
    #expect(parsed.bindings.first?.arg == "d")
    #expect(parsed.bindings.first?.mods == .maskControl)
}

@Test(arguments: ["\n", "\r\n"])
func editingListsKeepsTheirCommentsAndPosition(newline: String) {
    let original = ["# apps", "floating = com.apple.calculator # utilities",
                    "# cycle", "layouts = bsp, wide # preferred order", "window-margins = false", ""]
        .joined(separator: newline)
    let doc = ConfigDocument(text: original)
    doc.config.floating = ["com.apple.calculator", "com.example.#utility"]
    doc.config.layouts = [.wide, .bsp]
    let saved = doc.serialize()
    let expected = ["# apps", "floating = com.apple.calculator, com.example.##utility # utilities",
                    "# cycle", "layouts = wide, bsp # preferred order", "window-margins = false", ""]
        .joined(separator: newline)
    #expect(saved == expected)
    let reopened = ConfigDocument(text: saved)
    #expect(reopened.config.errors.isEmpty)
    #expect(reopened.config.floating == doc.config.floating)
    #expect(reopened.config.layouts == doc.config.layouts)
    reopened.config.floating = []
    reopened.config.layouts = [.bsp]
    let editedAgain = reopened.serialize()
    #expect(editedAgain == ["# apps", "floating =  # utilities", "# cycle",
                            "layouts = bsp # preferred order", "window-margins = false", ""]
        .joined(separator: newline))
    #expect(Config.parse(editedAgain).floating.isEmpty)
}

@Test func editingListsUpdatesTheLastAssignment() {
    let text = "floating = com.example.first\nfloating = com.example.last # active\n"
        + "layouts = bsp\nlayouts = wide # active\n"
    let doc = ConfigDocument(text: text)
    doc.config.floating = []
    doc.config.layouts = [.tall]
    let saved = doc.serialize()
    #expect(saved == "floating = com.example.first\nfloating =  # active\n"
        + "layouts = bsp\nlayouts = tall # active\n")
    #expect(Config.parse(saved).floating.isEmpty)
    #expect(Config.parse(saved).layouts == [.tall])
}

@Test func editingMissingListsAddsAssignments() {
    let doc = ConfigDocument(text: "# personal config\n")
    doc.config.floating = ["com.example.Utility"]
    doc.config.layouts = [.tall]
    let saved = doc.serialize()
    #expect(saved == "# personal config\nlayouts = tall\nfloating = com.example.Utility\n")
    #expect(Config.parse(saved).floating == doc.config.floating)
    #expect(Config.parse(saved).layouts == doc.config.layouts)
}
