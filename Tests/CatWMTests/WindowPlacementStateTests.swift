import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct WindowPlacementStateTests {
    @Test(arguments: [[true, false], [false, true], [true, true]])
    func fullscreenOrMinimizedWindowsBlockPlacement(_ flags: [Bool]) {
        #expect(WindowPlacementState.decode(flags)?.blocked == true)
    }

    @Test func anUnsupportedFullscreenFlagDoesNotHideTheMinimizedFlag() throws {
        var error = AXError.attributeUnsupported
        let unsupported = try #require(AXValueCreate(.axError, &error))
        #expect(WindowPlacementState.decode([unsupported, true])?.blocked == true)
        #expect(WindowPlacementState.decode([true, unsupported])?.blocked == true)
        #expect(WindowPlacementState.decode([unsupported, false])?.blocked == false)
        #expect(WindowPlacementState.decode([NSNull(), NSNull()])?.blocked == false)
    }

    @Test func incompleteRepliesRequireIndividualReads() {
        #expect(WindowPlacementState.decode([]) == nil)
        #expect(WindowPlacementState.decode([false]) == nil)
        #expect(WindowPlacementState.decode([false, false, true]) == nil)
        #expect(WindowPlacementState.decode([false, false])?.blocked == false)
    }
}
