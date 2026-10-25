import AppKit
@testable import CatWM
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

    @Test func aScopedManagerTurnsOffWhatActsOnTheWholeMac() {
        let manager = WindowManager(scope: WindowScope(pids: [10]))
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
}
