@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct WorkspaceKeyTests {
    @Test func aSpaceWorkspaceIsNotAnCatWMWorkspace() {
        let key = WindowManager.spaceWorkspace(display: "ABC-123", space: 42)
        #expect(key == "space:ABC-123:42")
        #expect(key.hasPrefix(WindowManager.spacePrefix))
    }
}
