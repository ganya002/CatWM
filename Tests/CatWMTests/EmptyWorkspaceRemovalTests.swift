import AppKit
@testable import CatWM
import CatWMFakes
@testable import CatWMKit
import Testing

@MainActor @Suite(.serialized) struct EmptyWorkspaceRemovalTests {
    private final class Removals { var spaces: [UInt64] = [] }

    private func makeManager(_ removals: Removals) async -> WindowManager {
        let fake = FakeBackend()
        let screen = fake.addScreen()
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(allWindows: [CGWindowInfo(id: 1, pid: 1, bounds: .zero)], spaces: [1: [1]])
        }, readApplications: { [] })
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: [1]) { continuation.resume() }
        }
        let manager = WindowManager(backend: fake, config: .parse(defaultText), scanner: scanner)
        manager.config.virtualWorkspaces = true
        manager.config.removesEmptyWorkspaces = true
        manager.desktops.nativeCatalog.synchronize([.init(id: screen.uuid, spaces: [1, 2, 3])])
        manager.desktopRemover = { space, _ in removals.spaces.append(space) }
        return manager
    }

    @Test func aWorkspaceSwitchedToInAFastBurstSurvivesTheEmptySweep() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        for target in ["2", "3", "1", "2"] { manager.holdSwitchTarget(target) }
        manager.releaseEmptyWorkspaces()
        _ = await poll(0.5, every: 10_000_000) { false }
        #expect(!removals.spaces.contains(2))
    }

    @Test func aSweepWaitingToRunSkipsAWorkspaceTheUserSwitchedToMeanwhile() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        manager.releaseEmptyWorkspaces()
        manager.holdSwitchTarget("3")
        _ = await poll(0.5, every: 10_000_000) { false }
        #expect(!removals.spaces.contains(3))
    }

    @Test func anUntargetedEmptyWorkspaceIsStillRemoved() async {
        let removals = Removals()
        let manager = await makeManager(removals)
        manager.releaseEmptyWorkspaces()
        let removed = await poll(2, every: 10_000_000) { removals.spaces.contains(3) }
        #expect(removed)
    }
}
