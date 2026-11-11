import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct FakeInputGuardTests {
    private struct Setup {
        let fake: FakeBackend
        let manager: WindowManager
        let window: CGWindowID
    }

    private func start() async -> Setup {
        let fake = FakeBackend()
        fake.addScreen()
        let manager = fake.makeManager()
        let window = fake.addWindow()
        await fake.settle(manager)
        return Setup(fake: fake, manager: manager, window: window)
    }

    @Test func aTestProcessCannotReachTheRealInput() {
        #expect(RealInput.isBlocked)
    }

    @Test func switchingWorkspaceIsRecordedInTheFakeAndPostsNothingReal() async {
        let setup = await start()
        let (fake, manager) = (setup.fake, setup.manager)
        let refused = RealInput.refusals
        manager.dispatch("workspace", "2")
        #expect(fake.currentDesktop == 2)
        #expect(fake.desktopSwitches == [2])
        #expect(fake.inputs.count == 1)
        manager.dispatch("workspace", "1")
        #expect(fake.desktopSwitches == [2, 1])
        #expect(RealInput.refusals == refused)
    }

    @Test func movingAWindowToAWorkspaceCarriesItThereInTheFake() async {
        let setup = await start()
        let (fake, manager, window) = (setup.fake, setup.manager, setup.window)
        let refused = RealInput.refusals
        manager.dispatch("movetoworkspace", "3")
        #expect(await fake.wait(manager) { !manager.desktops.movingToSpace && fake.currentDesktop == 3 })
        #expect(fake.desktop(of: window) == 3)
        #expect(fake.desktopSwitches == [2, 3])
        #expect(RealInput.refusals == refused)
    }

    @Test func aFakeManagerReadsThePointerFromTheFake() async {
        let setup = await start()
        let (fake, manager) = (setup.fake, setup.manager)
        fake.setPointer(CGPoint(x: 12, y: 34))
        #expect(manager.mouseLocation() == CGPoint(x: 12, y: 34))
        manager.warpPointer(to: CGPoint(x: 5, y: 6))
        #expect(fake.inputs == [.warp(CGPoint(x: 5, y: 6))])
    }
}
