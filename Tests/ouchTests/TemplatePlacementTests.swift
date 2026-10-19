import CoreGraphics
import Foundation
@testable import ouch
import Testing

@Suite struct TemplatePlacementTests {
    @Test func aHeldWindowStaysHeldUntilANewerClearScan() {
        let held = Date(timeIntervalSince1970: 50_000)
        let older = held.addingTimeInterval(-0.2)
        let newer = held.addingTimeInterval(0.2)
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: newer, heldSince: held, minimized: true, fullscreen: false, restoring: false
        ))
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: newer, heldSince: held, minimized: false, fullscreen: true, restoring: false
        ))
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: newer, heldSince: held, minimized: true, fullscreen: true, restoring: false
        ))
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: older, heldSince: held, minimized: false, fullscreen: false, restoring: false
        ))
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: held, heldSince: held, minimized: false, fullscreen: false, restoring: false
        ))
        #expect(!TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: newer, heldSince: held, minimized: false, fullscreen: false, restoring: true
        ))
        #expect(TemplatePlacementPlan.releaseHeldWindow(
            scanStarted: newer, heldSince: held, minimized: false, fullscreen: false, restoring: false
        ))
    }

    @Test func aMinimizedZoomedWindowOnThePreferredDisplayKeepsZoom() {
        let template = WorkspaceTemplateTests().template()
        let saved = template.windows[0]
        let collapsed = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "only", "builtin": "only"]
        )
        #expect(saved.minimized && saved.zoomed)
        #expect(collapsed["only"] == "external")
        #expect(TemplatePlacementPlan.zoomedWindow(
            savedDisplay: saved.display, window: saved.windowID, zoomed: saved.zoomed,
            preferredSavedDisplay: collapsed["only"]) == saved.windowID)
        let separate = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "desk", "builtin": "laptop"]
        )
        #expect(TemplatePlacementPlan.zoomedWindow(
            savedDisplay: "builtin", window: 9, zoomed: true, preferredSavedDisplay: separate["laptop"]) == 9)
        #expect(TemplatePlacementPlan.zoomedWindow(
            savedDisplay: "builtin", window: 9, zoomed: true, preferredSavedDisplay: collapsed["only"]) == nil)
        #expect(TemplatePlacementPlan.zoomedWindow(
            savedDisplay: saved.display, window: saved.windowID, zoomed: false,
            preferredSavedDisplay: collapsed["only"]) == nil)
    }

    @Test func anUnrelatedWriterIsOutsideThePlacementBarrier() {
        #expect(TemplatePlacementPlan.writerBarrier(placed: Set([11]), busy: Set([11, 77])) == Set([11]))
    }

    @Test func anEmptyDesktopMembershipDoesNotPlaceTheWindow() {
        #expect(TemplatePlacementPlan.desktopMove(membership: [], destination: 5) == .unavailable)
        #expect(TemplatePlacementPlan.desktopMove(membership: [5], destination: 5) == .stay)
        #expect(TemplatePlacementPlan.desktopMove(membership: [8], destination: 5) == .move)
    }
}
