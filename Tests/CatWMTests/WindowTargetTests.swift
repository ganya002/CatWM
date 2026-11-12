import AppKit
import CatWMFakes
@testable import CatWMKit
import Testing

@Suite(.timeLimit(.minutes(1))) @MainActor struct WindowTargetTests {
    @Test func aWindowCommandActsOnTheGivenWindowNotTheFocusedOne() async throws {
        let fake = FakeBackend()
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        fake.addScreen(frame: frame, visible: frame)
        let first = fake.addWindow(pid: -401, frame: CGRect(x: 50, y: 50, width: 600, height: 400))
        let second = fake.addWindow(pid: -402, frame: CGRect(x: 700, y: 50, width: 600, height: 400))
        let manager = fake.makeManager()
        #expect(await fake.settle(manager))

        let args: [String: JSON] = ["window": .int(Int(second))]
        try CommandRegistry.execute("setfloating", args, client: nil, manager: manager)
        #expect(await fake.settle(manager))
        #expect(try #require(manager.windows[second]).isFloating)
        #expect(try !#require(manager.windows[first]).isFloating)

        try CommandRegistry.execute("togglefloating", args, client: nil, manager: manager)
        #expect(await fake.settle(manager))
        #expect(try !#require(manager.windows[second]).isFloating)
    }

    @Test func anUnknownWindowIsAnErrorAndOnlyWindowCommandsTakeOne() {
        let manager = WindowManager(config: Config())
        #expect(throws: ControlError.self) {
            try CommandRegistry.execute("killactive", ["window": .int(424_242)], client: nil, manager: manager)
        }
        #expect(throws: ControlError.self) {
            try CommandRegistry.execute("workspace", ["workspace": .string("2"), "window": .int(1)], client: nil,
                                        manager: manager)
        }
        let targeted = Set(WindowActions.all.filter(\.takesWindow).map(\.name))
        #expect(targeted == ["movewindowtomonitor", "togglefloating", "setfloating", "settiled", "resizeactive",
                             "moveactive", "centerwindow", "fullscreen", "minimize", "killactive",
                             "movetoworkspace", "movetoworkspacesilent"])
    }
}
