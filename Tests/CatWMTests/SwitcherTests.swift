@testable import CatWM
import Testing

private let safari = SwitcherItem(id: 1, pid: 10, app: "Safari", title: "Apple Developer", workspace: "1")
private let slack = SwitcherItem(id: 2, pid: 20, app: "Slack", title: "general", workspace: "2 · Chat")
private let notes = SwitcherItem(id: 3, pid: 30, app: "Notes", title: "Shopping list", workspace: "3")
private let safariTwo = SwitcherItem(id: 4, pid: 10, app: "Safari", title: "Swift Forums", workspace: "1")
private let all = [safari, slack, notes, safariTwo]

@Suite struct SwitcherSearchTests {
    @Test func anEmptyQueryKeepsTheRecentOrder() {
        #expect(SwitcherSearch.results(all, query: "") == all)
    }

    @Test func letterGapsStillMatchAndMissesDrop() {
        #expect(SwitcherSearch.results(all, query: "sfr").map(\.id) == [4, 1])
        #expect(SwitcherSearch.results(all, query: "zzz").isEmpty)
    }

    @Test func appTitleAndWorkspaceAllMatch() {
        #expect(SwitcherSearch.results(all, query: "forums").map(\.id) == [4])
        #expect(SwitcherSearch.results(all, query: "chat").map(\.id) == [2])
        #expect(SwitcherSearch.results(all, query: "NOTES").first?.id == 3)
    }

    @Test func wordStartsRankAboveScatteredLetters() {
        #expect(SwitcherSearch.results(all, query: "sl").first?.id == 2)
        #expect(SwitcherSearch.results(all, query: "sh").first?.id == 3)
    }

    @Test func laterContiguousMatchesRankAboveScatteredMatches() {
        let scattered = SwitcherItem(id: 5, pid: 1, app: "", title: "axxxb")
        let contiguous = SwitcherItem(id: 6, pid: 2, app: "", title: "a---ab")
        #expect(SwitcherSearch.results([scattered, contiguous], query: "ab").map(\.id) == [6, 5])
    }

    @Test func instantJumpNeedsExactlyOnePrefixMatch() {
        #expect(SwitcherSearch.soleJump(all, query: "sl")?.id == 2)
        #expect(SwitcherSearch.soleJump(all, query: "sa") == nil)
        #expect(SwitcherSearch.soleJump(all, query: "swift f")?.id == 4)
        #expect(SwitcherSearch.soleJump(all, query: "") == nil)
    }
}

@Suite struct SwitcherModelTests {
    @Test func selectionWrapsBothWays() {
        let model = SwitcherModel()
        model.begin(all, selection: 1)
        model.move(-2)
        #expect(model.selected == safariTwo)
        model.move(1)
        #expect(model.selected == safari)
    }

    @Test func typingSelectsTheBestMatchAndErasingRestoresTheList() {
        let model = SwitcherModel()
        model.begin(all, selection: 1)
        model.type("n")
        model.type("o")
        #expect(model.selected == notes)
        model.erase(all: true)
        #expect(model.results == all && model.selection == 0)
    }

    @Test func theAppFilterKeepsOneAppAndTheSelectedWindow() {
        let model = SwitcherModel()
        model.begin(all, selection: 3)
        model.toggleAppFilter()
        #expect(model.results == [safari, safariTwo] && model.selected == safariTwo)
        model.toggleAppFilter()
        #expect(model.results == all && model.selected == safariTwo)
    }

    @Test func backspaceOnAnEmptySearchClearsTheAppFilter() {
        let model = SwitcherModel()
        model.begin(all, selection: 3)
        model.toggleAppFilter()
        model.type("f")
        model.erase(all: false)
        #expect(model.appFilter != nil)
        model.erase(all: false)
        #expect(model.appFilter == nil && model.results == all)
    }

    @Test func removingAnAppDropsItsWindowsAndItsFilter() {
        let model = SwitcherModel()
        model.begin(all, selection: 0)
        model.toggleAppFilter()
        model.remove { $0.pid == 10 }
        #expect(model.appFilter == nil && model.results == [slack, notes])
    }
}

@Test func spaceLabelsNumberDesktopsAndNameFullScreenSpaces() {
    let main = Spaces.DisplaySpaces(ids: [11, 12, 13, 14], desktops: [0, 1, 3], current: 0)
    let side = Spaces.DisplaySpaces(ids: [21, 0], desktops: [0], current: 0)
    #expect(WindowManager.spaceLabels([main, side]) == [
        11: "Desktop 1", 12: "Desktop 2", 13: "Full Screen", 14: "Desktop 3", 21: "Desktop 1"
    ])
}
