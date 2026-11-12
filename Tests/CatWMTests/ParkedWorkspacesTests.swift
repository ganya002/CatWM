import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct ParkedWorkspacesTests {
    private let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    private func world() async throws -> (FakeBackend, WindowManager, CGWindowID, CGWindowID) {
        let fake = FakeBackend()
        fake.addScreen(frame: screenFrame, visible: screenFrame)
        let first = fake.addWindow(pid: -301, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let second = fake.addWindow(pid: -302, frame: CGRect(x: 700, y: 50, width: 600, height: 400))
        let manager = fake.makeManager { $0.parkedWorkspaces = true }
        #expect(await fake.settle(manager))
        return (fake, manager, first, second)
    }

    private func parked(_ fake: FakeBackend, _ manager: WindowManager, _ id: CGWindowID) -> Bool {
        manager.isParked(fake.frame(of: id), fake.screens())
    }

    @Test func parkedModeTurnsNativeDesktopsOff() async throws {
        let (_, manager, _, _) = try await world()
        #expect(manager.config.parkedWorkspaces)
        #expect(!manager.config.virtualWorkspaces)
        #expect(manager.namedWorkspaces)
        #expect(manager.currentWorkspace == "1")
    }

    @Test func aWindowMovedAwayIsParkedAndComesBackWhenItsWorkspaceShows() async throws {
        let (fake, manager, first, second) = try await world()
        #expect(manager.workspaceOf[first] == "1" && manager.workspaceOf[second] == "1")
        manager.moveToWorkspaceCommand("2", follow: false, window: try #require(manager.windows[second]))
        #expect(await fake.settle(manager))
        #expect(manager.workspaceOf[second] == "2", "got \(String(describing: manager.workspaceOf[second])) shown \(manager.virtualShown) mon \(manager.monitorOf)")
        #expect(parked(fake, manager, second))
        #expect(!parked(fake, manager, first))
        #expect(fake.frame(of: first).width > 1000, "the window left alone takes the whole screen")

        manager.showWorkspaceCommand("2")
        #expect(await fake.settle(manager))
        #expect(manager.currentWorkspace == "2", "cur \(String(describing: manager.currentWorkspace)) shown \(manager.virtualShown) scr \(String(describing: manager.currentScreen()?.uuid))")
        #expect(parked(fake, manager, first))
        #expect(!parked(fake, manager, second))

        manager.showWorkspaceCommand("1")
        #expect(await fake.settle(manager))
        #expect(!parked(fake, manager, first))
        #expect(parked(fake, manager, second))
    }

    @Test func aPinnedFloatingWindowFollowsTheShownWorkspace() async throws {
        let (fake, manager, first, second) = try await world()
        let pinned = try #require(manager.windows[first])
        manager.setFloating(true, for: pinned)
        #expect(await fake.settle(manager))
        try CommandRegistry.execute("pin", ["window": .int(Int(first))], client: nil, manager: manager)
        manager.showWorkspaceCommand("2")
        #expect(await fake.settle(manager))
        #expect(manager.workspaceOf[first] == "2")
        #expect(!parked(fake, manager, first))
        #expect(parked(fake, manager, second))
    }

    @Test func stepsAreHyprlandNumbers() {
        #expect(WindowManager.parkedStep(from: "3", by: 1) == "4")
        #expect(WindowManager.parkedStep(from: "1", by: -1) == "1")
        #expect(WindowManager.parkedStep(from: "name", by: 1) == nil)
    }
}
