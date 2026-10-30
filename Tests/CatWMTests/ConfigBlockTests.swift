@testable import CatWM
import Testing

@Suite struct ConfigBlockTests {
    @Test func unmatchedClosingBraceReportsItsLine() {
        let config = Config.parse("# config\r\n} # stray brace\r\nwindow-margins = false\r\n")
        #expect(config.errors == ["line 2: unexpected `}` (no open block)"])
        #expect(!config.windowMargins)
    }

    @Test func unclosedBlocksReportTheirOpeningLines() {
        let config = Config.parse("# config\nanimations {\n  enabled = false\n  general {")
        #expect(config.errors == [
            "line 2: block `animations` is missing a closing `}`",
            "line 4: block `general` is missing a closing `}`"
        ])
        #expect(!config.animate)
    }

    @Test func aClosedInnerBlockDoesNotHideAnUnclosedOuterBlock() {
        let config = Config.parse("general {\n  animations {\n  }\n")
        #expect(config.errors == ["line 1: block `general` is missing a closing `}`"])
    }

    @Test func balancedBlocksStillParseAndRoundTrip() {
        let text = "general {\n  window-margins = false\n  nested {\n    window-margin-size = 24\n  }\n}\n"
            + "animations { # motion\n  enabled = false\n}\n"
        let document = ConfigDocument(text: text)
        #expect(document.config.errors.isEmpty)
        #expect(!document.config.windowMargins)
        #expect(document.config.windowMarginSize == 24)
        #expect(!document.config.animate)
        #expect(document.serialize() == text)
    }
}
