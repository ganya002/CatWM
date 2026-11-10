import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct WindowCreationTimingTests {
    @Test func creationSchedulesDiscoveryWithoutTheRefreshDebounce() {
        let manager = WindowManager(config: .parse(defaultText))
        defer { manager.refreshWork?.cancel() }
        manager.handle(kAXWindowCreatedNotification, AXUIElementCreateApplication(-1))
        #expect(manager.refreshWork != nil)
        #expect(manager.refreshDeadline <= DispatchTime.now())
    }

    @Test func creationAdvancesAnAlreadyScheduledRefresh() {
        let manager = WindowManager(config: .parse(defaultText))
        defer { manager.refreshWork?.cancel() }
        manager.scheduleRefresh(after: 1)
        manager.handle(kAXWindowCreatedNotification, AXUIElementCreateApplication(-1))
        #expect(manager.refreshDeadline <= DispatchTime.now())
    }
}
