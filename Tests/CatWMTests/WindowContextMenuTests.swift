@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowContextMenuTests {
    final class Runs { var list: [String] = [] }

    func input(_ runs: Runs = Runs(), grouped: Bool = false, tiled: Bool = true, workspaces: [String] = [],
               displays: [WindowContextMenu.Display] = []) -> WindowContextMenu.Input {
        WindowContextMenu.Input(
            floating: !tiled, grouped: grouped, tiled: tiled, workspaces: workspaces, currentWorkspace: "2",
            displays: displays,
            keys: { dispatcher, args in dispatcher == "togglefloating" ? ["C"] : args == "3" ? ["Shift", "3"] : [] },
            run: { runs.list.append($0 + " " + $1) }
        )
    }

    @Test func plainTiledWindowGetsTheBasicRows() {
        let ids = WindowContextMenu.items(input()).map(\.id)
        #expect(ids == ["float", "fullscreen", "swap", "s1", "retile"])
    }

    @Test func floatingWindowHasNoSwapRow() {
        #expect(!WindowContextMenu.items(input(tiled: false)).map(\.id).contains("swap"))
    }

    @Test func groupedWindowGetsMoveOutOfGroup() {
        #expect(WindowContextMenu.items(input(grouped: true)).map(\.id).contains("out"))
    }

    @Test func rowsShowTheBoundKeyAndRunTheDispatcher() {
        let runs = Runs()
        let items = WindowContextMenu.items(input(runs))
        #expect(items[0].shortcut == ["C"])
        #expect(items[1].shortcut.isEmpty)
        items[0].action?()
        #expect(runs.list == ["togglefloating "])
    }

    @Test func workspaceSubmenuChecksTheCurrentOne() throws {
        let runs = Runs()
        let items = WindowContextMenu.items(input(runs, workspaces: ["1", "2", "3"]))
        let row = try #require(items.first { $0.id == "workspace" })
        #expect(row.children.map(\.checked) == [false, true, false])
        #expect(row.children[2].shortcut == ["Shift", "3"])
        row.children[2].action?()
        #expect(runs.list == ["movetoworkspace 3"])
    }

    @Test func displayRowAppearsOnlyWithAnotherDisplay() throws {
        #expect(!WindowContextMenu.items(input()).map(\.id).contains("display"))
        let runs = Runs()
        let other = WindowContextMenu.Display(index: 1, name: "Studio", keys: [])
        let row = try #require(WindowContextMenu.items(input(runs, displays: [other])).first { $0.id == "display" })
        row.children[0].action?()
        #expect(runs.list == ["movewindow mon:1"])
    }
}
