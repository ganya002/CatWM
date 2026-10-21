import CoreGraphics
import Foundation
import Testing
@testable import WindowSession

@Suite struct KittyAdapterTests {
    private let json = """
    [{"id": 1, "platform_window_id": 77, "tabs": [
      {"title": "one", "is_active": false, "windows": [{"cwd": "/tmp", "is_active": true, "foreground_processes": []}]},
      {"title": "two", "is_active": true, "windows": [
        {"cwd": "/Users/a b", "is_active": false, "foreground_processes": []},
        {"cwd": "/Users/a", "is_active": true, "foreground_processes": [{"cwd": "/Users/a/Code"}]}]}]}]
    """

    @Test func readsOneFolderForEachTabAndTheActiveTab() {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        let window = AppStateCapture.Window(id: 77, bundleID: "net.kovidgoyal.kitty", title: "two", frame: frame)
        let found = KittyAdapter.parse(json, windows: [window])
        #expect(found.count == 1)
        #expect(found[0].state.tabs == ["file:///tmp/", "file:///Users/a/Code/"])
        #expect(found[0].state.selected == 1)
        #expect(found[0].frame == frame)
        #expect(AppStateCapture.attach(found, to: [window])[77] == found[0].state)
    }

    @Test func badOutputGivesNoWindows() {
        #expect(KittyAdapter.parse("not json", windows: []).isEmpty)
    }

    @Test func sessionHasOneQuotedTabForEachFolderAndFocusesTheSelectedOne() {
        let folders = [URL(fileURLWithPath: "/tmp"), URL(fileURLWithPath: "/Users/a b's")]
        let expected = "new_tab\ncd '/tmp'\nlaunch\nnew_tab\ncd '/Users/a b'\\''s'\nlaunch\nfocus\n"
        #expect(KittyAdapter.session(folders: folders, selected: 1) == expected)
    }
}

@Suite struct WezTermAdapterTests {
    private let json = """
    [{"window_id": 0, "tab_id": 0, "pane_id": 0, "window_title": "main",
      "cwd": "file://host/Users/a%20b/", "is_active": true},
     {"window_id": 0, "tab_id": 1, "pane_id": 1, "window_title": "main", "cwd": "file://host/tmp", "is_active": false},
     {"window_id": 0, "tab_id": 1, "pane_id": 2, "window_title": "main", "cwd": "file://host/var", "is_active": true},
     {"window_id": 1, "tab_id": 2, "pane_id": 3, "window_title": "other", "cwd": "", "is_active": true}]
    """

    @Test func groupsPanesIntoTabsAndWindowsAndSkipsWindowsWithoutFolders() {
        let found = WezTermAdapter.parse(json)
        #expect(found.count == 1)
        #expect(found[0].title == "main")
        #expect(found[0].state.tabs == ["file:///Users/a%20b/", "file:///var/"])
    }

    @Test func findsTheWindowOfAPane() {
        #expect(WezTermAdapter.windowID(ofPane: 3, in: json) == 1)
        #expect(WezTermAdapter.windowID(ofPane: 9, in: json) == nil)
    }
}
