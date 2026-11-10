@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Foundation
import SQLite3
import Testing

@Suite struct WindowTabsTests {
    private let frame = CGRect(x: 0, y: 25, width: 800, height: 600)

    private func window(_ id: CGWindowID, _ bundle: String = "com.apple.Terminal",
                        frame: CGRect? = nil) -> AppStateCapture.Window {
        AppStateCapture.Window(id: id, bundleID: bundle, title: "zsh", frame: frame ?? self.frame)
    }

    @Test func aHiddenWindowWithTheFrameOfAVisibleOneIsABackgroundTab() {
        let tabs = WindowTabs.background([window(1), window(2), window(3)], onScreen: [2])
        #expect(tabs == [1: 2, 3: 2])
    }

    @Test func otherWindowsAreNotTabs() {
        let moved = CGRect(x: 40, y: 25, width: 800, height: 600)
        #expect(WindowTabs.background([window(1), window(2, "com.apple.finder")], onScreen: [2]).isEmpty)
        #expect(WindowTabs.background([window(1), window(2, frame: moved)], onScreen: [2]).isEmpty)
        #expect(WindowTabs.background([window(1), window(2)], onScreen: []).isEmpty)
        #expect(WindowTabs.background([window(1), window(2)], onScreen: [1, 2]).isEmpty)
    }

    @Test func finderTabsWithOneFrameBecomeOneWindow() {
        let other = CGRect(x: 900, y: 25, width: 500, height: 400)
        let merged = WindowTabs.merged([
            ScriptedWindow(title: "Code", frame: frame, state: AppState(tabs: ["file:///Users/a/Code/"])),
            ScriptedWindow(title: "Other", frame: other, state: AppState(tabs: ["file:///tmp/"])),
            ScriptedWindow(title: "Docs", frame: frame, state: AppState(tabs: ["file:///Users/a/Docs/"]))
        ])
        #expect(merged.count == 2)
        #expect(merged[0].state.tabs == ["file:///Users/a/Code/", "file:///Users/a/Docs/"])
        #expect(merged[0].state.current == "file:///Users/a/Code/")
    }
}

@Suite struct TerminalGroupTests {
    @Test func writesAWindowGroupWithOneTabForEachFolder() throws {
        let folders = [URL(fileURLWithPath: "/tmp"), URL(fileURLWithPath: "/Users/a b")]
        let data = try #require(TerminalGroup.file(folders: folders, selected: 1, profile: "Basic"))
        let root = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(root["type"] as? String == "Window Group")
        let windows = try #require(root["WindowList"] as? [[String: Any]])
        #expect(windows.count == 1)
        #expect(windows[0]["ShowsTabBar"] as? Bool == true)
        let tabs = try #require(windows[0]["Window Settings"] as? [[String: Any]])
        #expect(tabs.map { $0["TabSelected"] as? Bool } == [false, true])
        #expect(tabs[1]["Tab Working Directory URL"] as? String == "file:///Users/a%20b/")
        #expect(tabs[1]["Tab Working Directory URL String"] as? String == "file:///Users/a%20b")
        #expect(tabs[0]["Tab Settings Name"] as? String == "Basic")
    }
}

@Suite struct ProjectGuessTests {
    private let projects = [URL(fileURLWithPath: "/Users/a/Code/catwm"), URL(fileURLWithPath: "/Users/a/Code"),
                            URL(fileURLWithPath: "/Users/a/site.code-workspace")]

    @Test func readsFoldersAndWorkspacesFromTheRecentList() {
        let json = """
        {"entries":[{"folderUri":"file:///Users/a/Code/catwm"},{"fileUri":"file:///Users/a/notes.md"},
        {"workspace":{"id":"1","configPath":"file:///Users/a/site.code-workspace"}},
        {"folderUri":"vscode-remote://ssh-remote%2Bbox/home/a"}]}
        """
        #expect(CodeEditorAdapter.recentProjects(json).map(\.absoluteString)
            == ["file:///Users/a/Code/catwm", "file:///Users/a/site.code-workspace"])
        #expect(CodeEditorAdapter.recentProjects("broken").isEmpty)
    }

    @Test func theDeepestFolderThatHoldsTheOpenFileWins() {
        let found = ProjectGuess.pick(projects, title: "", document: "file:///Users/a/Code/catwm/Package.swift")
        #expect(found?.absoluteString == "file:///Users/a/Code/catwm")
    }

    @Test func theNamedProjectWinsOverARecentlyOpenedNestedFolder() throws {
        let window = AppStateCapture.Window(id: 1, bundleID: "com.microsoft.VSCode",
                                          title: "main.swift — Code — Visual Studio Code",
                                          frame: .zero, document: "file:///Users/a/Code/catwm/main.swift")
        let captured = try #require(ProjectGuess.windows([window], projects: projects).first)
        #expect(captured.state.current == projects[1].absoluteString)
    }

    @Test func aNamedWorkspaceWinsOverTheFolderContainingItsOpenFile() {
        #expect(ProjectGuess.pick(projects, title: "main.swift — site (Workspace) — Cursor",
                                  document: "file:///Users/a/Code/catwm/main.swift") == projects[2])
    }

    @Test func theOpenFileDistinguishesProjectsWithTheSameName() {
        let other = URL(fileURLWithPath: "/Users/a/Other/catwm")
        #expect(ProjectGuess.pick([other] + projects, title: "main.swift — catwm — Cursor",
                                  document: "file:///Users/a/Code/catwm/main.swift") == projects[0])
    }

    @Test func aWorkspaceFileDoesNotOwnOtherFilesInItsParentFolder() {
        #expect(ProjectGuess.pick(projects, title: "notes.md — Visual Studio Code",
                                  document: "file:///Users/a/notes.md") == nil)
        let other = URL(fileURLWithPath: "/Users/a/other.code-workspace")
        #expect(ProjectGuess.pick(projects + [other], title: "notes.md — other (Workspace) — Cursor",
                                  document: "file:///Users/a/notes.md") == other)
    }

    @Test func theOpenWorkspaceFileIdentifiesItsOwnProject() {
        #expect(ProjectGuess.pick(projects, title: "", document: "file:///Users/a/site.code-workspace")
            == projects[2])
    }

    @Test func theTitleNamesTheFolderOrWorkspace() {
        #expect(ProjectGuess.pick(projects, title: "main.swift — catwm — Cursor", document: nil)?.lastPathComponent
            == "catwm")
        #expect(ProjectGuess.pick(projects, title: "index.html - site (Workspace) - Visual Studio Code",
                                  document: nil)?.lastPathComponent == "site.code-workspace")
        #expect(ProjectGuess.pick(projects, title: "Welcome", document: nil) == nil)
    }

    @Test func findsTheXcodeProjectAboveAFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let sources = root.appendingPathComponent("App/Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("App.xcodeproj"),
                                                withIntermediateDirectories: true)
        let file = sources.appendingPathComponent("main.swift")
        #expect(ProjectGuess.xcodeProject(file)?.lastPathComponent == "App.xcodeproj")
        let project = root.appendingPathComponent("Other.xcworkspace")
        #expect(ProjectGuess.xcodeProject(project) == project)
    }
}

@Suite struct SQLiteReadTests {
    @Test func readsTextRowsAndToleratesAMissingFile() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var database: OpaquePointer?
        #expect(sqlite3_open(path, &database) == SQLITE_OK)
        sqlite3_exec(database, "create table t (v text); insert into t values ('a'), ('b');", nil, nil, nil)
        sqlite3_close(database)
        #expect(SQLiteRead.strings(path, "select v from t order by v") == ["a", "b"])
        #expect(SQLiteRead.strings(path, "select nope from t").isEmpty)
        #expect(SQLiteRead.strings("/no/such.db", "select 1").isEmpty)
    }
}
