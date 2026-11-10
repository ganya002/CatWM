@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

struct TabStripRevealTests {
    let slot = CGRect(x: 100, y: 200, width: 800, height: 600)
    let kitty = TitleBar(lights: CGRect(x: 8, y: 8, width: 52, height: 16), contentTop: 32, controlTop: 32)

    @Test func theEmptyTitleBarShowsTheTabs() {
        #expect(TabStripReveal.reveals(CGPoint(x: 500, y: 225), slot: slot, bar: kitty, revealed: false))
        #expect(!TabStripReveal.reveals(CGPoint(x: 500, y: 235), slot: slot, bar: kitty, revealed: false))
    }

    @Test func theTrafficLightsDoNotShowTheTabs() {
        #expect(!TabStripReveal.reveals(CGPoint(x: 120, y: 216), slot: slot, bar: kitty, revealed: false))
        #expect(!TabStripReveal.reveals(CGPoint(x: 165, y: 216), slot: slot, bar: kitty, revealed: false))
        #expect(TabStripReveal.reveals(CGPoint(x: 120, y: 190), slot: slot, bar: kitty, revealed: false))
    }

    @Test func anUnknownTitleBarUsesTheLeadBand() {
        let electron = TitleBar(lights: CGRect(x: 18, y: 18, width: 52, height: 16), contentTop: 0, controlTop: nil)
        #expect(electron.clearTop == nil)
        #expect(TabStripReveal.reveals(CGPoint(x: 500, y: 208), slot: slot, bar: electron, revealed: false))
        #expect(!TabStripReveal.reveals(CGPoint(x: 500, y: 215), slot: slot, bar: electron, revealed: false))
        #expect(TabStripReveal.reveals(CGPoint(x: 500, y: 208), slot: slot, bar: nil, revealed: false))
    }

    @Test func aShownStripStaysWhileThePointerIsOnIt() {
        #expect(TabStripReveal.reveals(CGPoint(x: 120, y: 216), slot: slot, bar: kitty, revealed: true))
        #expect(!TabStripReveal.reveals(CGPoint(x: 500, y: 200 + TabStrip.height + 1), slot: slot, bar: kitty,
                                         revealed: true))
    }
}

extension TabStripRevealTests {
    func reveals(_ x: CGFloat, _ y: CGFloat, heading: CGVector) -> Bool {
        TabStripReveal.reveals(CGPoint(x: x, y: y), slot: slot, bar: kitty, revealed: false, heading: heading)
    }

    @Test func movingTowardTheTrafficLightsDoesNotShowTheTabs() {
        #expect(!reveals(200, 228, heading: CGVector(dx: -6, dy: -1)))
        #expect(!reveals(146, 231, heading: CGVector(dx: 0, dy: -4)))
        #expect(reveals(200, 228, heading: CGVector(dx: 6, dy: 0)))
        #expect(reveals(140, 195, heading: CGVector(dx: 0, dy: -4)))
    }
}
