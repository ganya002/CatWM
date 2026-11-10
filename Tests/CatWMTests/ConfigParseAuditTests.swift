@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Test func badBoolValueKeepsTheDefault() {
    let config = Config.parse("window-margins = ture\nanimations {\nenabled = maybe\n}\n")
    #expect(config.windowMargins)
    #expect(config.animate)
    #expect(config.errors.count == 2)
}

@Test func goodBoolValuesStillApply() {
    let config = Config.parse("window-margins = off\nanimations {\nenabled = no\n}\n")
    #expect(!config.windowMargins)
    #expect(!config.animate)
    #expect(config.errors.isEmpty)
}

@Test func crlfErrorsGiveTheRightLine() {
    let config = Config.parse("animate = true\r\nnot an option\r\nwindow-margins = false\r\n")
    #expect(config.errors == ["line 2: expected `key = value`"])
    #expect(!config.windowMargins)
}

@Test(arguments: ["bind", "binde"], ["notakey|1|2", "1|notakey|2", "1|2|notakey"])
func anInvalidKeyListDoesNotInstallPartialBinds(_ kind: String, _ keys: String) {
    let config = Config.parse("""
    bind = CTRL, space, sort
    \(kind) = CTRL, \(keys), toggledim
    bind = CTRL, 9, workspace, 9
    """)
    #expect(config.errors == ["line 2: unknown key `notakey`"])
    #expect(config.bindings.map(\.dispatcher) == ["sort", "workspace"])
    #expect(config.bindings.map(\.arg) == ["", "9"])
    let firstWorkspace = config.workspaceBindings.first { $0.keyCode == keyCodes["1"] && $0.mods == .maskControl }
    #expect(firstWorkspace?.dispatcher == "workspace")
    #expect(firstWorkspace?.arg == "1")
}

@Test(arguments: ["1|2|3", "1..3"])
func aValidKeyRangeInstallsEveryBind(_ keys: String) {
    let config = Config.parse("""
    submap = window
    binde = CTRL SHIFT, \(keys), movetoworkspace, 4..6
    """)
    #expect(config.errors.isEmpty)
    #expect(config.bindings.map(\.keyCode) == [keyCodes["1"], keyCodes["2"], keyCodes["3"]])
    #expect(config.bindings.map(\.arg) == ["4", "5", "6"])
    #expect(config.bindings.allSatisfy { $0.repeats && $0.submap == "window" })
}
