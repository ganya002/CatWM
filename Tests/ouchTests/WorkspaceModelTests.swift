// Tests: the workspace bookkeeping value the window manager and the Sort snapshot share.
import CoreGraphics
import Testing
@testable import ouch

@Suite struct WorkspaceModelTests {
    @Test func theShownSetFollowsEveryChange() {
        var m = WorkspaceModel()
        #expect(!m.isShown("1"))
        m.show("1", on: "A")
        m.shown["B"] = "2"
        #expect(m.isShown("1") && m.isShown("2"))
        m.show("3", on: "A")
        #expect(!m.isShown("1") && m.isShown("3"))
        m.shown["B"] = nil
        #expect(!m.isShown("2"))
        m.shown = [:]
        #expect(!m.isShown("3"))
        #expect(!m.isShown(nil))
    }

    @Test func forgetRemovesEveryTraceOfAWindow() {
        var m = WorkspaceModel()
        m.assign(7, to: "1"); m.assign(8, to: "1")
        m.order = [7, 8]
        m.noteFocus(8); m.noteFocus(7)
        m.lastFocused["1"] = 7
        m.forget(7)
        #expect(m.workspaceOf[7] == nil)
        #expect(m.order == [8])
        #expect(m.focusStamps[7] == nil)
        #expect(m.focusOrder == [8])
        #expect(m.lastFocused["1"] == nil)
        // A new window that gets the reused ID starts with no history.
        #expect(m.mostRecent(of: [7]) == nil)
        #expect(m.mostRecent(of: [7, 8]) == 8)
    }

    @Test func noteFocusKeepsTheMostRecentFirst() {
        var m = WorkspaceModel()
        m.noteFocus(1); m.noteFocus(2); m.noteFocus(1)
        #expect(m.focusOrder == [1, 2])
        #expect(m.mostRecent(of: [1, 2]) == 1)
        let clock = m.focusClock
        m.noteFocus(1) // already the latest: no new stamp
        #expect(m.focusClock == clock)
    }

    @Test func focusOrderIsCapped() {
        var m = WorkspaceModel()
        for id in 1...100 { m.noteFocus(CGWindowID(id)) }
        #expect(m.focusOrder.count == 80)
        #expect(m.focusOrder.first == 100)
    }

    @Test func swapAndKeepChangeOnlyTheirWindows() {
        var m = WorkspaceModel()
        m.assign(1, to: "1"); m.assign(2, to: "2"); m.assign(3, to: WindowManager.spaceWorkspace(display: "A", space: 9))
        m.swapWorkspaces(1, 2)
        #expect(m.workspaceOf[1] == "2" && m.workspaceOf[2] == "1")
        m.keepWorkspaces { !$0.hasPrefix(WindowManager.spacePrefix) }
        #expect(m.workspaceOf.count == 2 && m.workspaceOf[3] == nil)
    }

    @Test func resetKeepsOrderAndFocusHistory() {
        var m = WorkspaceModel()
        m.assign(1, to: "1"); m.order = [1]; m.noteFocus(1)
        m.show("1", on: "A"); m.virtualShown["A"] = "1"; m.monitorOf["1"] = "A"; m.lastFocused["1"] = 1
        _ = m.states["1", default: ScreenState(layout: .tall)]
        m.resetWorkspaces()
        #expect(m.workspaceOf.isEmpty && m.shown.isEmpty && m.virtualShown.isEmpty && m.monitorOf.isEmpty && m.lastFocused.isEmpty)
        #expect(!m.isShown("1"))
        #expect(m.order == [1] && m.focusOrder == [1])
    }

    @Test func aSnapshotDoesNotChangeWithTheModel() {
        var m = WorkspaceModel()
        let st = ScreenState(layout: .tall)
        st.ratio = 0.6; st.mainCount = 2; st.zoomed = 4
        m.states["1"] = st
        m.assign(4, to: "1"); m.order = [4]; m.lastFocused["1"] = 4
        let snap = m.snapshot()
        st.layout = .bsp; st.ratio = 0.3
        m.assign(4, to: "2"); m.order = []; m.lastFocused["1"] = nil
        #expect(snap.states["1"]?.layout == .tall)
        #expect(snap.states["1"]?.ratio == 0.6)
        #expect(snap.states["1"]?.mainCount == 2)
        #expect(snap.states["1"]?.zoomed == 4)
        #expect(snap.workspaceOf[4] == "1")
        #expect(snap.order == [4])
        #expect(snap.lastFocused["1"] == 4)
    }
}
