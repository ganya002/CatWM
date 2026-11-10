@testable import CatWM
@testable import CatWMKit
import CoreGraphics
import Testing

@Suite struct SortRenumberSameNumberTests {
    @Test func typingTheOwnNumberWithALeadingZeroChangesNothing() {
        let model = SortModel()
        let item = SortItem(id: 1, title: "A", app: "App", bundleID: nil, icon: nil, recency: 1)
        let lane = SortLane(workspace: "1", name: "", layout: .tall, ids: [1])
        model.plans = ["d": SortPlan(display: "d", items: [1: item], lanes: [lane],
                                         existing: ["1"], taken: [], active: "1")]
        model.current = "d"
        model.renumber(lane.id, to: "01")
        #expect(model.notice == nil)
        #expect(model.plan.lanes[0].workspace == "1")
    }
}
