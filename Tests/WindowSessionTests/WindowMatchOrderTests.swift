import CoreGraphics
import Foundation
import Testing
@testable import WindowSession

@Suite struct WindowMatchOrderTests {
    private func saved(_ id: CGWindowID, _ frame: CGRect, title: String = "zsh",
                       document: String? = nil) -> SavedWindow {
        SavedWindow(bundleID: "com.apple.Terminal", appName: "Terminal", title: title, document: document,
                    display: "desk", frame: frame, floating: false, minimized: false, fullscreen: false,
                    zoomed: false, focused: false, windowID: id, launchDate: nil)
    }

    private func candidate(_ id: CGWindowID, _ frame: CGRect?, title: String = "zsh",
                           document: String? = nil) -> WindowCandidate {
        WindowCandidate(windowID: id, bundleID: "com.apple.Terminal", title: title, document: document,
                        launchDate: nil, allowsGenericFallback: true, newlyOpened: true, frame: frame)
    }

    @Test func sameTitlesMatchTheNearestFrame() {
        let left = CGRect(x: 0, y: 25, width: 700, height: 800)
        let right = CGRect(x: 700, y: 25, width: 700, height: 800)
        let first = saved(1, left), second = saved(2, right)
        let result = WindowMatch.assign([first, second], candidates: [candidate(50, right), candidate(60, left)])
        #expect(result[first.id] == 60)
        #expect(result[second.id] == 50)
    }

    @Test func withoutFramesTheOldestSavedWindowGetsTheOldestWindow() {
        let older = saved(5, .zero), newer = saved(9, .zero)
        let result = WindowMatch.assign([newer, older], candidates: [candidate(80, nil), candidate(70, nil)])
        #expect(result[older.id] == 70)
        #expect(result[newer.id] == 80)
    }

    @Test func aBetterScoreStillWinsOverAnyFrame() {
        let frame = CGRect(x: 0, y: 25, width: 700, height: 800)
        let window = saved(1, frame, title: "notes", document: "file:///tmp/notes.txt")
        let near = candidate(10, frame, title: "notes")
        let exact = candidate(20, CGRect(x: 900, y: 500, width: 200, height: 200), title: "other",
                              document: "file:///tmp/notes.txt")
        #expect(WindowMatch.assign([window], candidates: [near, exact])[window.id] == 20)
    }

    @Test func aWindowWithSavedTabsAcceptsANewWindowThatShowsAnotherPage() {
        var window = saved(1, .zero, title: "News", document: "https://news.example/")
        window.state = AppState(tabs: ["https://news.example/"])
        let loading = candidate(30, nil, title: "Loading", document: "https://news.example/home")
        #expect(WindowMatch.assign([window], candidates: [loading])[window.id] == 30)
        window.state = nil
        #expect(WindowMatch.assign([window], candidates: [loading]).isEmpty)
    }

    @Test func aWindowWithSavedTabsWaitsForItsAdapterInsteadOfTakingTheStartupWindow() {
        var window = saved(1, .zero, title: "Wikipedia")
        window.state = AppState(tabs: ["https://a.test/", "https://b.test/"])
        let startup = candidate(30, nil, title: "New tab")
        #expect(WindowMatch.assign([window], candidates: [startup], awaitingAdapter: [window.id]).isEmpty)
        #expect(WindowMatch.assign([window], candidates: [startup])[window.id] == 30)
        let titled = candidate(40, nil, title: "Wikipedia")
        #expect(WindowMatch.assign([window], candidates: [startup, titled],
                                   awaitingAdapter: [window.id])[window.id] == 40)
    }
}
