@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct DesktopPollingTests {
    @Test func supersededRequestStopsWithoutAnotherServerRead() async {
        var current = true
        var reads = 0
        let result = await poll(1, every: 1_000_000, while: { current }, until: {
            reads += 1
            current = false
            return false
        })
        #expect(!result && reads == 1)
    }

    @Test func aRequestAlreadySupersededDoesNotReadTheServer() async {
        var reads = 0
        let result = await poll(1, while: { false }, until: { reads += 1; return true })
        #expect(!result && reads == 0)
    }

    @Test func matchingAppearanceCompletesWithoutWaiting() async {
        var reads = 0
        let result = await poll(1, while: { true }, until: { reads += 1; return true })
        #expect(result && reads == 1)
    }

    @Test func unchangedRequestStillWaitsForAppearance() async {
        var reads = 0
        let result = await poll(30, every: 1_000_000, while: { true }, until: {
            reads += 1
            return reads == 3
        })
        #expect(result && reads == 3)
    }
}
