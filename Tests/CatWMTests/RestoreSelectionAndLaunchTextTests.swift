@testable import CatWM
@testable import CatWMKit
import Foundation
import Testing

@Suite struct RestoreTabSelectionTests {
    @Test func aDuplicateFolderKeepsTheSelectedTab() {
        let state = AppState(tabs: ["file:///p/", "file:///p/", "file:///p/"], selected: 2)
        let kept = state.kept { URL(string: $0)?.isFileURL == true }
        #expect(kept.tabs.count == 3)
        #expect(kept.selected == 2)
    }

    @Test func aRemovedTabMovesTheSelectionWithTheKeptTabs() {
        let state = AppState(tabs: ["https://a/", "javascript:void(0)", "https://a/", "https://b/"], selected: 2)
        let kept = state.kept(BrowserScript.isOpenable)
        #expect(kept.tabs == ["https://a/", "https://a/", "https://b/"])
        #expect(kept.selected == 1)
    }
}

@Suite struct LaunchTextSpacingTests {
    @Test func theTargetKeepsItsOwnSpaces() throws {
        let screenshot = "~/Desktop/Screenshot 2026-10-22 at 10.00.00\u{202F}PM.png"
        let request = try #require(LaunchRequest(screenshot + " workspace=2"))
        #expect(request.target == screenshot)
        #expect(request.workspace == "2")
        #expect(LaunchRequest("/tmp/My  Folder")?.target == "/tmp/My  Folder")
    }
}
