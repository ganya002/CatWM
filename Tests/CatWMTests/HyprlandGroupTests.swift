import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct HyprlandGroupTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func world() async throws -> (FakeBackend, WindowManager, CGWindowID, CGWindowID) {
        let fake = FakeBackend()
        fake.addScreen(frame: screenFrame, visible: screenFrame)
        let first = fake.addWindow(pid: -401, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let second = fake.addWindow(pid: -402, frame: CGRect(x: 700, y: 50, width: 600, height: 400))
        let manager = fake.makeManager { $0.parkedWorkspaces = true }
        #expect(await fake.settle(manager))
        manager.focus(try #require(manager.windows[first]))
        #expect(await fake.settle(manager))
        return (fake, manager, first, second)
    }

    @Test func aToggledGroupTakesInNewWindowsUntilLocked() async throws {
        let (fake, manager, first, second) = try await world()
        manager.dispatch("togglegroup", "")
        #expect(manager.tabs.armed.contains(first))
        #expect(!manager.tabs.isGrouped(second))

        let third = fake.addWindow(pid: -403)
        #expect(await fake.settle(manager))
        #expect(manager.tabs.group(of: first)?.members == [first, third])

        manager.focus(try #require(manager.windows[first]))
        #expect(await fake.settle(manager))
        manager.dispatch("lockactivegroup", "")
        #expect(manager.tabs.isLocked(third))
        let fourth = fake.addWindow(pid: -404)
        #expect(await fake.settle(manager))
        #expect(!manager.tabs.isGrouped(fourth))

        manager.focus(try #require(manager.windows[first]))
        #expect(await fake.settle(manager))
        manager.dispatch("togglegroup", "")
        #expect(await fake.settle(manager))
        #expect(!manager.tabs.isGrouped(first) && !manager.tabs.isGrouped(third))
        #expect(manager.tabs.armed.isEmpty)
    }

    @Test func dragMadeTabsNeverCollect() {
        var tabs = TabGroups()
        tabs.join(2, onto: 1)
        #expect(!tabs.collects(1))
        tabs.toggleArmed(5)
        #expect(tabs.collects(5))
        tabs.join(6, onto: 5)
        tabs.toggleLocked(6)
        #expect(!tabs.collects(5))
        tabs.remove(6)
        #expect(tabs.armed == [5])
        #expect(tabs.isLocked(5), "the group of one keeps its lock")
    }
}
