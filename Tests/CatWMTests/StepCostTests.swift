@testable import CatWM
@testable import CatWMKit
import Testing

@Suite struct StepCostTests {
    @Test func aNewWindowHasNoLead() {
        #expect(StepCost().lead == 0)
    }

    @Test func theLeadFollowsTheWriteCost() {
        var cost = StepCost()
        cost.add(0.02)
        #expect(cost.lead == 0.02)
        cost.add(0.03)
        #expect(abs(cost.lead - 0.024) < 0.0001)
    }

    @Test func aStalledWriteDoesNotPushTheLeadPastTheLimit() {
        var cost = StepCost()
        cost.add(0.5)
        #expect(cost.lead == 0.05)
    }
}
