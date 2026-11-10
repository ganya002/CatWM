import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct ApplicationLaunchTimingTests {
    @Test func launchSchedulesDiscoveryWithoutAnInitialWait() {
        let manager = WindowManager(config: .parse(defaultText))
        defer { manager.refreshWork?.cancel() }
        manager.applicationLaunched(.current)
        #expect(manager.refreshWork != nil)
        #expect(manager.refreshDeadline <= DispatchTime.now())
    }

    @Test func launchAdvancesAnAlreadyScheduledRefresh() {
        let manager = WindowManager(config: .parse(defaultText))
        defer { manager.refreshWork?.cancel() }
        manager.scheduleRefresh(after: 1)
        manager.applicationLaunched(.current)
        #expect(manager.refreshDeadline <= DispatchTime.now())
    }
}
