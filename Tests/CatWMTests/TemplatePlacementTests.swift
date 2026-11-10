@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Foundation
import Testing

@Suite struct TemplatePlacementTests {
    @Test func aMinimizedZoomedWindowOnThePreferredDisplayKeepsZoom() {
        let template = WorkspaceTemplateTests().template()
        let saved = template.windows[0]
        let collapsed = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "only", "builtin": "only"]
        )
        #expect(saved.minimized && saved.zoomed)
        #expect(collapsed["only"] == "external")
        let separate = TemplatePlacementPlan.preferredDisplays(
            template, mapping: ["external": "desk", "builtin": "laptop"]
        )
        #expect(separate["desk"] == "external")
        #expect(separate["laptop"] == "builtin")
    }

    @Test func anEmptyDesktopMembershipDoesNotPlaceTheWindow() {
        #expect(TemplatePlacementPlan.desktopMove(membership: [], destination: 5) == .unavailable)
        #expect(TemplatePlacementPlan.desktopMove(membership: [5], destination: 5) == .stay)
        #expect(TemplatePlacementPlan.desktopMove(membership: [8], destination: 5) == .move)
    }
}
