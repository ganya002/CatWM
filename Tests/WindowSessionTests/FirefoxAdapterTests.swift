import CoreGraphics
import Foundation
import Testing
@testable import WindowSession

@Suite struct FirefoxAdapterTests {
    private let session = """
    {"windows": [
      {"selected": 2, "screenX": 100, "screenY": "50", "width": 800, "height": 600, "tabs": [
        {"index": 1, "pinned": true, "entries": [{"url": "https://a.test/", "title": "A"}]},
        {"index": 2, "entries": [{"url": "https://b.test/old", "title": "Old"},
                                 {"url": "https://b.test/new", "title": "Page B"}]},
        {"index": 1, "entries": [{"url": "about:newtab", "title": "New Tab"}]},
        {"index": 1, "entries": [{"url": "https://c.test/", "title": "C"}]}]},
      {"selected": 1, "tabs": [{"index": 1, "entries": [{"url": "about:blank"}]}]}
    ]}
    """

    @Test func readsTheCurrentEntryOfEachWebTabAndTheSelectedTab() {
        let found = FirefoxAdapter.parse(Data(session.utf8), windows: [])
        #expect(found.count == 1)
        #expect(found[0].state.tabs == ["https://a.test/", "https://b.test/new", "https://c.test/"])
        #expect(found[0].state.selected == 1)
        #expect(found[0].frame == CGRect(x: 100, y: 50, width: 800, height: 600))
        #expect(found[0].title == "Page B")
    }

    @Test func aWindowWhoseTitleStartsWithTheTabTitleTakesItsFrame() {
        let frame = CGRect(x: 5, y: 6, width: 700, height: 500)
        let window = AppStateCapture.Window(id: 9, bundleID: "org.mozilla.firefox", title: "Page B — Mozilla Firefox",
                                            frame: frame)
        let found = FirefoxAdapter.parse(Data(session.utf8), windows: [window])
        #expect(found[0].frame == frame)
        #expect(AppStateCapture.attach(found, to: [window])[9]?.tabs.count == 3)
    }

    @Test func badJSONGivesNoWindows() {
        #expect(FirefoxAdapter.parse(Data("nope".utf8), windows: []).isEmpty)
    }

    @Test func mozLZ4RoundTrips() throws {
        let data = Data(String(repeating: "https://example.test/path ", count: 200).utf8)
        let packed = try #require(MozLZ4.encode(data))
        #expect(packed.count < data.count)
        #expect(MozLZ4.decode(packed) == data)
        #expect(MozLZ4.decode(Data("junk".utf8)) == nil)
    }

    @Test func aFileWithoutALockIsNotLocked() {
        #expect(!FirefoxAdapter.isLocked(URL(fileURLWithPath: "/nonexistent/.parentlock")))
        #expect(!FirefoxAdapter.isLocked(FileManager.default.temporaryDirectory))
    }
}
