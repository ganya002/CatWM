@testable import CatWM
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
