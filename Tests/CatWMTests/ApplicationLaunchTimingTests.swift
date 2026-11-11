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

    @Test func aScopedInstanceIgnoresAnAppOutsideItsScope() {
        let pid = NSRunningApplication.current.processIdentifier
        let manager = WindowManager(config: .parse(defaultText), scope: WindowScope(pids: [pid + 1]))
        defer { manager.refreshWork?.cancel() }
        manager.applicationLaunched(.current)
        #expect(manager.refreshWork == nil)
        manager.applicationTerminated(pid)
        #expect(manager.refreshWork == nil)
    }

    @Test func aScopedInstanceFollowsAnAppInsideItsScope() {
        let pid = NSRunningApplication.current.processIdentifier
        let manager = WindowManager(config: .parse(defaultText), scope: WindowScope(pids: [pid]))
        defer { manager.refreshWork?.cancel() }
        manager.applicationLaunched(.current)
        #expect(manager.refreshWork != nil)
        manager.refreshWork?.cancel()
        manager.refreshWork = nil
        manager.applicationTerminated(pid)
        #expect(manager.refreshWork != nil)
    }
}
