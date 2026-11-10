@testable import CatWM
import Testing

@Suite struct StepCostTests {
    @Test func aNewWindowHasNoLead() {
        #expect(StepCost().lead == 0)
    }

    @Test func theLeadFollowsTheWriteCost() {
        var cost = StepCost()
        cost.add(0.02)
        #expect(cost.lead == 0.02)
        cost.add(0.01)
        #expect(abs(cost.lead - 0.016) < 0.0001)
    }

    @Test func aSlowerWriteRaisesTheLeadFasterThanAFasterOneLowersIt() {
        var rising = StepCost(), falling = StepCost()
        rising.add(0.01); rising.add(0.03)
        falling.add(0.03); falling.add(0.01)
        #expect(rising.lead - 0.01 > 0.03 - falling.lead)
    }

    @Test func aStallDoesNotKeepTheLeadAtTheLimitAfterTheAppRecovers() {
        var cost = StepCost()
        cost.add(0.5)
        cost.add(0.005)
        cost.add(0.005)
        #expect(cost.lead < 0.025)
    }

    @Test func aStalledWriteDoesNotPushTheLeadPastTheLimit() {
        var cost = StepCost()
        cost.add(0.5)
        #expect(cost.lead == 0.05)
    }
}
