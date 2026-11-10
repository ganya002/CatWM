import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct SortCloseAndWorkspaceStepTests {
    @Test func aBusyAppIsNotSeenAsWindowless() {
        #expect(!WindowManager.reportsNoWindows(.cannotComplete, nil))
        #expect(!WindowManager.reportsNoWindows(.failure, nil))
        #expect(!WindowManager.reportsNoWindows(.success, [AXUIElementCreateApplication(-1)] as CFArray))
        #expect(WindowManager.reportsNoWindows(.success, [] as CFArray))
        #expect(WindowManager.reportsNoWindows(.noValue, nil))
    }

    @Test func windowsThatWillBeClosedAgainStayHidden() {
        let shown = WindowManager.shownAfterTry([1, 2, 3, 4], left: [2, 3], forced: [4], sheeted: [3])
        #expect(shown == [1, 3])
    }

    @Test func occupiedStepStartsFromTheCurrentNumber() {
        let sorted = ["1", "3", "5"]
        let before: (String, String) -> Bool = { Int($0) ?? 0 < Int($1) ?? 0 }
        #expect(WindowManager.step(sorted, from: "2", by: 1, sortedBy: before) == "3")
        #expect(WindowManager.step(sorted, from: "2", by: -1, sortedBy: before) == "1")
        #expect(WindowManager.step(sorted, from: "6", by: 1, sortedBy: before) == "1")
        #expect(WindowManager.step(sorted, from: "0", by: -1, sortedBy: before) == "5")
        #expect(WindowManager.step(sorted, from: "3", by: 1, sortedBy: before) == "5")
        #expect(WindowManager.step([], from: "1", by: 1, sortedBy: before) == nil)
    }

    @Test func extremeOccupiedStepsWrapWithoutOverflow() {
        let sorted = ["1", "3", "5"]
        let before = WorkspaceReconciliation.workspaceSort
        #expect(WindowManager.step(sorted, from: "3", by: Int.max, sortedBy: before) == "5")
        #expect(WindowManager.step(sorted, from: "1", by: Int.min, sortedBy: before) == "3")
        #expect(WindowManager.step(sorted, from: "6", by: Int.max, sortedBy: before) == "1")
        #expect(WindowManager.step(sorted, from: "0", by: Int.min, sortedBy: before) == "3")
    }

    @Test @MainActor func aRemovedWorkspaceForgetsItsLabel() {
        let manager = WindowManager(config: .parse(defaultText))
        manager.labels["3"] = "Mail"
        manager.lastFocused["3"] = 7
        manager.forgetRemovedWorkspace("3")
        #expect(manager.labels["3"] == nil)
        #expect(manager.lastFocused["3"] == nil)
    }
}
