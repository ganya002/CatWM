@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct InvalidBindTests {
    @Test(arguments: ["bind", "binde"])
    func invalidKeyListDoesNotInstallPartOfABind(_ kind: String) throws {
        let config = Config.parse("""
        bind = CTRL, J, movefocus, d
        \(kind) = , H|not-a-key, movefocus, l
        bind = CTRL, K, movefocus, u
        """)

        #expect(config.errors == ["line 2: unknown key `not-a-key`"])
        let downCode = try #require(keyCodes["j"])
        let upCode = try #require(keyCodes["k"])
        #expect(config.bindings.map(\.keyCode) == [downCode, upCode])
        #expect(config.bindings.map(\.arg) == ["d", "u"])
        let hotkeys = Hotkeys()
        hotkeys.setBindings(config.bindings)
        let leftCode = try #require(keyCodes["h"])
        #expect(hotkeys.lookup(leftCode, []) == nil)
    }

    @Test func invalidKeyListDoesNotMakeASubmapUsable() {
        let config = Config.parse("""
        bind = CTRL, W, submap, window
        submap = window
        bind = , H|not-a-key, movefocus, l
        submap = reset
        """)

        #expect(config.errors == [
            "line 3: unknown key `not-a-key`",
            "`submap, window` enters a mode with no binds"
        ])
        #expect(config.bindings.map(\.submap) == [""])
    }

    @Test func validKeyListKeepsItsPairedArgumentsAndRepeatMode() {
        let config = Config.parse("""
        submap = window
        binde = , H|L, movefocus, l|r
        """)

        #expect(config.errors.isEmpty)
        #expect(config.bindings.map(\.arg) == ["l", "r"])
        #expect(config.bindings.count == 2)
        #expect(config.bindings.allSatisfy { $0.submap == "window" && $0.repeats })
    }
}
