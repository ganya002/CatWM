@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct TabStripStackTests {
    @Test func severalStripsUseTheOrderProducedByEarlierPlacements() {
        var stack = TabStripStack(windows: [1, 2, 11, 12, 3])
        #expect(stack.place(11, below: [1]) == .above(2))
        #expect(stack.place(12, below: [2]) == nil)
        #expect(stack.windows == [1, 11, 2, 12, 3])
        #expect(stack.place(11, below: [1]) == nil)
        #expect(stack.place(12, below: [2]) == nil)
    }

    @Test func theHighestGroupMemberAnchorsItsStrip() {
        var stack = TabStripStack(windows: [3, 2, 1, 11, 4])
        #expect(stack.place(11, below: [1, 2]) == .above(1))
        #expect(stack.windows == [3, 2, 11, 1, 4])
    }

    @Test func aNewStripIsIncludedInLaterPlacements() {
        var stack = TabStripStack(windows: [1, 2, 3])
        #expect(stack.place(11, below: [1], fallback: 1) == .above(2))
        #expect(stack.place(12, below: [2], fallback: 2) == .above(3))
        #expect(stack.windows == [1, 11, 2, 12, 3])
    }

    @Test func anOffscreenAnchorKeepsTheNativeRelativeOrderFallback() {
        var stack = TabStripStack(windows: [1, 2, 3])
        #expect(stack.place(11, below: [4, 5], fallback: 5) == .below(5))
        #expect(stack.windows == [1, 2, 3])
        #expect(stack.place(11, below: [4, 5]) == nil)
    }

    @Test func theBottomAnchorKeepsItsExistingBehaviour() {
        var stack = TabStripStack(windows: [1, 2, 11])
        #expect(stack.place(11, below: [2]) == nil)
        #expect(stack.place(12, below: [11]) == nil)
        #expect(stack.windows == [1, 2, 11])
    }
}
