import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite @MainActor struct StartupRetryTests {
    @Test func aStartupRetryWaitsForTheFirstScan() {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        manager.retryStartupScan()
        #expect(manager.refreshWork != nil)
    }

    @Test func aStartupRetryScansWhileAnAppCouldBecomeReadable() async {
        let fake = FakeBackend()
        fake.addScreen()
        fake.addWindow()
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))
        manager.refreshWork = nil
        manager.retryStartupScan()
        #expect(manager.refreshWork != nil)
    }

    @Test func aStartupRetryDoesNothingWhenNoAppIsRunning() async {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))
        manager.refreshWork = nil
        manager.retryStartupScan()
        #expect(manager.refreshWork == nil)
    }
}
