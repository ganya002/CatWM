// Tests: the names of per-Space workspaces, which key layout state and window assignments.
import CoreGraphics
import Testing
@testable import ouch

@Suite struct WorkspaceKeyTests {
    @Test func aSpaceWorkspaceIsNotAnOuchWorkspace() {
        let key = WindowManager.spaceWorkspace(display: "ABC-123", space: 42)
        #expect(key == "space:ABC-123:42")
        #expect(key.hasPrefix(WindowManager.spacePrefix))
    }

    @Test func eachDisplayAndSpaceHasItsOwnKey() {
        let keys: Set = [WindowManager.spaceWorkspace(display: "A", space: 1), WindowManager.spaceWorkspace(display: "A", space: 2),
                         WindowManager.spaceWorkspace(display: "B", space: 1)]
        #expect(keys.count == 3)
    }
}
