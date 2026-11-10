@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Foundation
import Testing

@Suite struct AppStateCaptureTests {
    private func window(_ id: CGWindowID, _ title: String, _ frame: CGRect) -> AppStateCapture.Window {
        AppStateCapture.Window(id: id, bundleID: "com.apple.Safari", title: title, frame: frame)
    }

    private func scripted(_ title: String, _ frame: CGRect?, _ url: String) -> ScriptedWindow {
        ScriptedWindow(title: title, frame: frame, state: AppState(tabs: [url]))
    }

    @Test func pairsEachScriptedWindowWithTheWindowAtTheSameFrame() {
        let left = CGRect(x: 0, y: 25, width: 700, height: 800)
        let right = CGRect(x: 700, y: 25, width: 700, height: 800)
        let states = AppStateCapture.attach(
            [scripted("Docs", right, "https://b.example"), scripted("Docs", left, "https://a.example")],
            to: [window(1, "Docs", left), window(2, "Docs", right)])
        #expect(states[1]?.tabs == ["https://a.example"])
        #expect(states[2]?.tabs == ["https://b.example"])
    }

    @Test func usesTheTitleWhenTheAppGivesNoFrame() {
        let frame = CGRect(x: 0, y: 25, width: 700, height: 800)
        let states = AppStateCapture.attach([scripted("Mail", nil, "https://mail.example")],
                                            to: [window(1, "News", frame), window(2, "Mail", frame)])
        #expect(states[1] == nil)
        #expect(states[2]?.tabs == ["https://mail.example"])
    }

    @Test func ignoresAWindowThatIsFarAwayAndTitledDifferently() {
        let states = AppStateCapture.attach(
            [scripted("Other", CGRect(x: 900, y: 500, width: 300, height: 300), "https://x.example")],
            to: [window(1, "Mine", CGRect(x: 0, y: 25, width: 700, height: 800))])
        #expect(states.isEmpty)
    }

    @Test func decodesScriptOutputAndKeepsTheSelectedTab() throws {
        let output = """
        [null, {"title": "Shell", "frame": [10, 20, 300, 400], "tabs": ["", "file:///tmp/", "file:///Users/"], \
        "selected": 2}, {"title": "Empty", "tabs": []}]
        """
        let windows = ScriptedEntry.decode(output).compactMap { $0.window() }
        let window = try #require(windows.first)
        #expect(windows.count == 1)
        #expect(window.frame == CGRect(x: 10, y: 20, width: 300, height: 400))
        #expect(window.state.tabs == ["file:///tmp/", "file:///Users/"])
        #expect(window.state.current == "file:///Users/")
    }

    @Test func badOutputGivesNoWindows() {
        #expect(ScriptedEntry.decode(nil).isEmpty)
        #expect(ScriptedEntry.decode("not json").isEmpty)
    }

    @Test func adaptersCoverEachSupportedApp() {
        for bundle in ["com.apple.Safari", "com.google.Chrome", "com.apple.Terminal", "com.googlecode.iterm2",
                       "com.apple.finder"] {
            #expect(AppAdapters.adapter(for: bundle) != nil)
        }
        #expect(AppAdapters.adapter(for: "com.example.editor") == nil)
    }

    @Test func browserRestoreSkipsScriptURLs() {
        #expect(BrowserScript.isOpenable("https://example.com"))
        #expect(!BrowserScript.isOpenable("javascript:alert(1)"))
        #expect(!BrowserScript.isOpenable("not a url"))
    }
}

@Suite struct SavedWindowCodingTests {
    @Test func readsAWindowSavedBeforeAppStateExisted() throws {
        let json = """
        {"id": "6F1A6D3E-8B0B-4C7E-9E52-1C1A2B3C4D5E", "bundleID": "com.apple.TextEdit", "appName": "TextEdit",
         "title": "Notes", "display": "desk", "frame": [[0, 25], [600, 400]], "floating": false,
         "minimized": false, "fullscreen": false, "zoomed": false, "focused": true, "windowID": 12}
        """
        let window = try JSONDecoder().decode(SavedWindow.self, from: Data(json.utf8))
        #expect(window.state == nil)
        #expect(window.launch == nil)
        #expect(window.frame == CGRect(x: 0, y: 25, width: 600, height: 400))
    }

    @Test func keepsAppStateAndLaunchThroughASave() throws {
        var window = SavedWindow(bundleID: "com.apple.Safari", appName: "Safari", title: "News", document: nil,
                                 display: "desk", frame: .zero, floating: false, minimized: false, fullscreen: false,
                                 zoomed: false, focused: false, windowID: 3, launchDate: nil)
        window.state = AppState(tabs: ["https://a.example", "https://b.example"], selected: 1)
        window.launch = LaunchSpec(arguments: ["--profile", "work"])
        let copy = try JSONDecoder().decode(SavedWindow.self, from: JSONEncoder().encode(window))
        #expect(copy == window)
    }
}
