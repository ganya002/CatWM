import AppKit
@testable import CatWM
@testable import CatWMKit
import Testing

@MainActor @Suite struct WindowScopeTests {
    @Test func aScopeReadsPidsAndAnOptionalDisplay() {
        #expect(WindowScope("pids:12") == WindowScope(pids: [12]))
        #expect(WindowScope("pids:12,34") == WindowScope(pids: [12, 34]))
        #expect(WindowScope("pids:12;display:ABC-1") == WindowScope(pids: [12], display: "ABC-1"))
        #expect(WindowScope("display:ABC-1;pids:12") == WindowScope(pids: [12], display: "ABC-1"))
    }

    @Test(arguments: ["", "pids:", "pids:,", "pids:12,", "pids:0", "pids:-3", "pids:a", "pid:12", "12",
                      "pids:12;display:", "pids:12;pids:13", "pids:12;screen:1", "pids:12;", "display:ABC"])
    func aBadScopeIsRefused(_ text: String) {
        #expect(WindowScope(text) == nil)
    }

    @Test func aScopedScannerHidesTheWindowsAndAppsOfOtherPids() async {
        let windows = [CGWindowInfo(id: 1, pid: 10, bounds: .zero), CGWindowInfo(id: 2, pid: 20, bounds: .zero)]
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(windows: windows, allWindows: windows, spaces: [1: [5], 2: [5]])
        }, readApplications: {
            [10, 20].map { RunningApplicationSnapshot(pid: $0, bundleID: "test.\($0)", regular: true, hidden: false) }
        }, scope: WindowScope(pids: [10]))
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: []) { continuation.resume() }
        }
        #expect(scanner.desktop.windows.map(\.pid) == [10])
        #expect(scanner.desktop.allWindows.map(\.pid) == [10])
        #expect(scanner.applications.map(\.pid) == [10])
    }

    @Test func anUnscopedScannerKeepsEveryPid() async {
        let windows = [CGWindowInfo(id: 1, pid: 10, bounds: .zero), CGWindowInfo(id: 2, pid: 20, bounds: .zero)]
        let scanner = WindowScanner(readDesktop: { _ in
            WindowServerObservation(windows: windows, allWindows: windows)
        }, readApplications: { [] })
        await withCheckedContinuation { continuation in
            scanner.observeDesktop(known: []) { continuation.resume() }
        }
        #expect(scanner.desktop.windows.map(\.pid) == [10, 20])
    }

    private static var globalConfig: Config {
        var config = Config()
        config.virtualWorkspaces = true
        config.focusFollowsMouse = true
        config.mouseFollowsFocus = true
        config.cursorActions = true
        config.dimOtherWindows = true
        config.blurOtherWindows = true
        return config
    }

    @Test func aScopedManagerTurnsOffWhatActsOnTheWholeMac() {
        let manager = WindowManager(config: Self.globalConfig, scope: WindowScope(pids: [10]))
        #expect(!manager.config.virtualWorkspaces)
        #expect(!manager.config.focusFollowsMouse)
        #expect(!manager.config.mouseFollowsFocus)
        #expect(!manager.config.cursorActions)
        #expect(!manager.config.dimOtherWindows)
        #expect(!manager.config.blurOtherWindows)
        manager.observe(pid: 20)
        #expect(manager.observing[20] == nil)
        let input = GlobalInput(scope: manager.scope, keys: nil)
        #expect(input == GlobalInput(scope: WindowScope(pids: [1]), keys: "off"))
        #expect(!input.keys && !input.capsLock && !input.mouseTaps)
    }

    @Test func keysCanBeTurnedOnForAScopedInstanceButCapsLockStaysOff() {
        let input = GlobalInput(scope: WindowScope(pids: [10]), keys: "on")
        #expect(input.keys)
        #expect(!input.capsLock && !input.mouseTaps)
    }

    @Test func anUnscopedInstanceKeepsEveryInput() {
        let input = GlobalInput(scope: nil, keys: nil)
        #expect(input.keys && input.capsLock && input.mouseTaps)
    }

    @Test func eachCommandIsAllowedOrRefusedInAScopedInstance() {
        let names = CommandRegistry.all.map(\.name)
        let allowed = WindowScope.allowedCommands, refused = WindowScope.refusedCommands
        for name in names {
            #expect(allowed.contains(name) != refused.contains(name), "decide if \(name) runs in a scoped instance")
        }
        #expect(allowed.union(refused) == Set(names))
    }

    @Test func aScopedInstanceRefusesACommandBeforeItRuns() {
        let scoped = WindowManager(config: Config(), scope: WindowScope(pids: [10]))
        let calls: [(String, [String: JSON])] = [
            ("grabtest", [:]), ("launch", [:]), ("dispatch", ["dispatcher": .string("Workspace")]),
            ("submap", ["name": .string("window")]),
            ("dispatch", ["dispatcher": .string("submap"), "arg": .string("window")])
        ]
        for (name, args) in calls {
            #expect(throws: ControlError.self) { try CommandRegistry.execute(name, args, client: nil, manager: scoped) }
        }
        #expect(throws: Never.self) { try CommandRegistry.execute("ping", [:], client: nil, manager: scoped) }
    }

    @Test func aScopedManagerDoesNotMoveThePointerOrTakeFocus() throws {
        let scoped = WindowManager(config: Config(), scope: WindowScope(pids: [10]))
        #expect(!scoped.input.pointerAndFocus)
        let display = try #require(NSScreen.screens.first)
        let away = CGRect(x: 90000, y: 90000, width: 100, height: 100)
        let empty = Screen(id: 0, uuid: "outside", frame: away, visible: away, isBuiltin: false, nsScreen: display)
        var warps: [CGPoint] = []
        scoped.warp = { warps.append($0) }
        scoped.focus(.monitor(empty))
        scoped.refocusCurrentWorkspace()
        scoped.warpPointer(to: away.origin)
        #expect(warps.isEmpty)
        #expect(scoped.focusSink == nil)
    }

    @Test func aScopedManagerDropsTheKeyBindsOfARefusedDispatcher() {
        let config = Config.parse("bind = ALT, w, submap, window\nbind = ALT, 2, workspace, 2\n"
            + "bind = ALT, h, movefocus, l\nsubmap = window\nbind = , escape, submap, reset\nsubmap = reset")
        let scoped = WindowManager(config: config, scope: WindowScope(pids: [10]))
        #expect(scoped.config.bindings.map(\.dispatcher) == ["movefocus"])
        let unscoped = WindowManager(config: config)
        #expect(unscoped.config.bindings.count == 4)
    }

    @Test func aScopedManagerRefusesWhatActsOutsideTheScope() {
        let scoped = WindowManager(config: Config(), scope: WindowScope(pids: [10]))
        for name in WindowScope.refusedCommands.sorted() {
            #expect(scoped.scopeRefusal(name)?.contains("not available in a scoped instance") == true)
        }
        #expect(scoped.scopeRefusal("movefocus") == nil)
        #expect(scoped.scopeRefusal("setlayout") == nil)
        let unscoped = WindowManager(config: Config())
        #expect(unscoped.scopeRefusal("workspace") == nil)
    }
}
