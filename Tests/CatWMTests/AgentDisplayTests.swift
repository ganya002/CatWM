import AppKit
@testable import CatWMKit
import os
import Testing

@MainActor @Suite struct AgentDisplayTests {
    @MainActor final class World {
        var windows: [CGWindowID: (pid: pid_t, frame: CGRect)] = [:]
        var refusals = 0
        var callbacks: [pid_t: @MainActor () -> Void] = [:]
        var queue: [@MainActor () -> Void] = []
        var clock = 0.0
        let switches = OSAllocatedUnfairLock(initialState: (disabled: 0, enabled: 0))
        var disabled: Int { switches.withLock { $0.disabled } }
        var enabled: Int { switches.withLock { $0.enabled } }
        let screen = CGRect(x: 3000, y: 0, width: 1920, height: 1080)
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("catwm-agent-\(UUID().uuidString)")

        var updates: WindowServerUpdates {
            WindowServerUpdates(disable: { [switches] in switches.withLock { $0.disabled += 1 }; return true },
                                enable: { [switches] in switches.withLock { $0.enabled += 1 } })
        }

        var access: AgentDisplay.Windows {
            .init(ids: { pid in self.windows.filter { $0.value.pid == pid }.keys.sorted() },
                  bounds: { self.windows[$0]?.frame },
                  move: { pid, id, point in
                      guard self.refusals == 0 else { self.refusals -= 1; return false }
                      guard let window = self.windows[id], window.pid == pid else { return false }
                      self.windows[id]?.frame.origin = point
                      return true
                  },
                  watch: { pid, created in self.callbacks[pid] = created; return NSObject() })
        }

        func open(_ id: CGWindowID, pid: pid_t, at origin: CGPoint = CGPoint(x: 100, y: 100)) {
            windows[id] = (pid, CGRect(origin: origin, size: CGSize(width: 600, height: 400)))
            callbacks[pid]?()
        }

        func display(owner: AnyObject? = nil, settle: Double = 0.25) -> AgentDisplay? {
            AgentDisplay(backing: .init(id: 4242, uuid: "AGENT-UUID", bounds: { self.screen }, owner: owner),
                         windows: access, updates: updates, home: home, settle: settle,
                         now: { self.clock },
                         schedule: { delay, work in self.queue.append { self.clock += delay; work() } })
        }

        func drain() {
            while !queue.isEmpty { queue.removeFirst()() }
        }
    }

    @Test func aWindowThatOpensLaterMovesOntoTheDisplayUnderOneLease() throws {
        let world = World()
        let display = try #require(world.display())
        display.claim(77)
        #expect(world.disabled == 0)
        world.open(1, pid: 77)
        #expect(world.windows[1]?.frame.origin == world.screen.origin)
        #expect((world.disabled, world.enabled) == (1, 1))
        world.open(2, pid: 77)
        world.drain()
        #expect(world.windows[2]?.frame.origin == world.screen.origin)
        #expect((world.disabled, world.enabled) == (2, 2))
    }

    @Test func anAppThatPlacesItsWindowAfterCreationIsMovedAgain() throws {
        let world = World()
        let display = try #require(world.display())
        display.claim(9)
        world.open(1, pid: 9, at: world.screen.origin)
        #expect((world.disabled, world.enabled) == (0, 0))
        world.windows[1]?.frame.origin = CGPoint(x: 182, y: 87)
        world.queue.removeFirst()()
        #expect(world.windows[1]?.frame.origin == world.screen.origin)
        #expect((world.disabled, world.enabled) == (1, 1))
    }

    @Test func claimingMovesTheWindowsThatAlreadyExistAndLeavesInsideOnesAlone() throws {
        let world = World()
        world.windows[1] = (5, CGRect(x: 10, y: 10, width: 300, height: 300))
        world.windows[2] = (5, CGRect(x: 3100, y: 50, width: 300, height: 300))
        world.windows[3] = (6, CGRect(x: 20, y: 20, width: 300, height: 300))
        let display = try #require(world.display())
        display.claim(5)
        world.drain()
        #expect(world.windows[1]?.frame.origin == world.screen.origin)
        #expect(world.windows[2]?.frame.origin == CGPoint(x: 3100, y: 50))
        #expect(world.windows[3]?.frame.origin == CGPoint(x: 20, y: 20))
        #expect(display.pids == [5])
    }

    @Test func aRefusedMoveIsRetriedUntilTheWindowLands() throws {
        let world = World()
        let display = try #require(world.display())
        display.claim(8)
        world.refusals = 2
        world.open(1, pid: 8)
        #expect(world.windows[1]?.frame.origin == CGPoint(x: 100, y: 100))
        world.drain()
        #expect(world.windows[1]?.frame.origin == world.screen.origin)
        #expect(world.enabled == 1)
    }

    @Test func aWindowThatNeverLandsStillReleasesTheLeaseAtTheDeadline() throws {
        let world = World()
        let display = try #require(world.display(settle: 0.05))
        display.claim(8)
        world.refusals = .max
        world.open(1, pid: 8)
        world.drain()
        #expect(world.enabled == 1)
        #expect(world.clock >= 0.05)
        #expect(world.windows[1]?.frame.origin == CGPoint(x: 100, y: 100))
    }

    @Test func theUsersCatWMReadsTheClaimAndTheClaimGoesWhenTheDisplayCloses() throws {
        let world = World()
        let display = try #require(world.display())
        let paths = try #require(InstancePaths(id: "agent-4242", home: world.home))
        let claims = ScopeClaims(folder: paths.instancesFolder)
        #expect(claims.claimedPids().isEmpty)
        display.claim(31)
        display.claim(32)
        #expect(claims.claimedPids() == [31, 32])
        let text = try String(contentsOf: paths.scopeFile, encoding: .utf8)
        #expect(ScopeClaim(text)?.scope.display == "AGENT-UUID")
        display.close()
        #expect(claims.claimedPids().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: paths.configFolder.path))
        #expect(display.bounds == .zero)
        display.claim(33)
        #expect(display.pids.isEmpty)
    }

    @Test func onlyWindowsOnTheDisplayAreListed() throws {
        let world = World()
        let display = try #require(world.display())
        display.claim(51)
        world.open(1, pid: 51, at: world.screen.origin)
        world.windows[2] = (51, CGRect(x: 100, y: 100, width: 300, height: 200))
        #expect(display.windowIDs().map(\.id) == [1])
        #expect(display.frame(of: 1)?.origin == world.screen.origin)
    }

    @Test func quittingWithNoAppsClosesTheDisplayAndTheClaim() async throws {
        let world = World()
        let display = try #require(world.display())
        let paths = try #require(InstancePaths(id: "agent-4242", home: world.home))
        display.claim(0)
        await display.quit()
        #expect(display.bounds == .zero)
        #expect(ScopeClaims(folder: paths.instancesFolder).claimedPids().isEmpty)
        await #expect(throws: AgentDisplay.LaunchError.failed) { try await display.launch("com.apple.TextEdit") }
    }

    @Test func droppingTheOwnerReleasesTheDisplayAndTheClaim() throws {
        let world = World()
        weak var released: NSObject?
        var display: AgentDisplay?
        do {
            let object = NSObject()
            released = object
            display = world.display(owner: object)
        }
        display?.claim(41)
        let paths = try #require(InstancePaths(id: "agent-4242", home: world.home))
        #expect(ScopeClaims(folder: paths.instancesFolder).claimedPids() == [41])
        #expect(released != nil)
        #expect(display?.uuid == "AGENT-UUID")
        #expect(display?.id == 4242)
        display = nil
        #expect(released == nil)
        #expect(ScopeClaims(folder: paths.instancesFolder).claimedPids().isEmpty)
    }

    @Test func aMissingPrivateDisplayReportsUnavailableInsteadOfCrashing() {
        #expect(AgentDisplay(backing: nil) == nil)
    }

    @Test func aDisplayIdThatIsNotTheAgentDisplayIsNotOwned() {
        #expect(CGMainDisplayID() != 0)
        #expect(!AgentDisplay.owns(CGMainDisplayID()))
        let agentDisplays = NSScreen.screens.filter { $0.displayID.map(AgentDisplay.owns) ?? false }
        #expect(NSScreen.userScreens.count == NSScreen.screens.count - agentDisplays.count)
    }
}
