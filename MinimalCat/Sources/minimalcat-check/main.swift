import AppKit
import MinimalCatCore
import MinimalCatSystem

// Drives the real engine against real windows through Accessibility, and reads every result back.
// `minimalcat-check` opens its own test windows in a child process and touches no other window.
// `minimalcat-check --windows N` is that child.

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--windows", let count = Int(arguments[2]) {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let windows = (1...count).map { index in
        let window = NSWindow(contentRect: CGRect(x: 120 * index, y: 120 * index, width: 640, height: 420),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Minimal Cat check \(index)"
        window.makeKeyAndOrderFront(nil)
        return window
    }
    _ = windows
    app.activate(ignoringOtherApps: true)
    app.run()
    exit(0)
}

@MainActor
final class Check {
    let system: AXSystem
    let engine: Engine
    var failures = 0

    init(scope: pid_t) {
        system = AXSystem(scope: [scope])
        engine = Engine(system: system)
    }

    func wait(_ seconds: TimeInterval = 2, until done: () -> Bool) -> TimeInterval? {
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            if done() { return Date().timeIntervalSince(start) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        return done() ? Date().timeIntervalSince(start) : nil
    }

    func report(_ name: String, _ passed: Bool, _ detail: String) {
        if !passed { failures += 1 }
        print("\(passed ? "PASS" : "FAIL")  \(name)  \(detail)")
    }

    func focus(_ window: WindowInfo) {
        system.focus(window.id)
        _ = wait { system.focusedWindow() == window.id }
        engine.focused(window.id)
    }

    func expectFrame(_ name: String, _ window: WindowID, _ target: CGRect) {
        let took = wait { system.frame(of: window).map { Geometry.approxEqual($0, target) } ?? false }
        let actual = system.frame(of: window).map { "\($0)" } ?? "unknown"
        report(name, took != nil, took.map { String(format: "landed in %.0f ms", $0 * 1000) }
            ?? "wanted \(target), got \(actual)")
        let seen = engine.windows().first { $0.id == window }?.frame
        report("\(name), the engine sees it", seen.map { Geometry.approxEqual($0, target) } ?? false,
               "saw \(seen.map { "\($0)" } ?? "nothing")")
    }

    func measureReads() {
        let start = Date()
        for _ in 0..<50 { engine.windows() }
        let each = Date().timeIntervalSince(start) / 50 * 1000
        print(String(format: "INFO  reading %d windows takes %.2f ms", engine.windows().count, each))
    }

    func run() {
        guard wait(5, until: { engine.windows().count >= 2 }) != nil else {
            report("test windows appear", false, "saw \(engine.windows().count) windows")
            return
        }
        let windows = engine.windows()
        let first = windows[0], second = windows[1]
        guard let display = Geometry.display(containing: first.frame, in: system.displays()) else { return }
        let start = system.frame(of: first.id) ?? first.frame
        focus(first)
        report("focus a test window", system.focusedWindow() == first.id,
               "focused \(String(describing: system.focusedWindow()))")
        placeAndUndo(first, on: display)
        moveAndFocus(first, second, on: display)
        restoreLayout(first, on: display, original: start)
        measureReads()
    }

    func placeAndUndo(_ first: WindowInfo, on display: Display) {
        for place in [Place.left, .right, .top, .bottom] {
            _ = engine.perform(.place(place))
            expectFrame("move \(place.rawValue)", first.id, Geometry.frame(for: place, on: display))
        }
        let beforeBig = Geometry.frame(for: .bottom, on: display)
        _ = engine.perform(.place(.big))
        expectFrame("make big", first.id, Geometry.frame(for: .big, on: display))
        _ = engine.perform(.place(.big))
        expectFrame("big again puts it back", first.id, beforeBig)
        _ = engine.perform(.undo)
        expectFrame("undo", first.id, Geometry.frame(for: .big, on: display))
        _ = engine.perform(.undo)
        expectFrame("undo again", first.id, beforeBig)
        _ = engine.perform(.redo)
        expectFrame("redo", first.id, Geometry.frame(for: .big, on: display))
    }

    func moveAndFocus(_ first: WindowInfo, _ second: WindowInfo, on display: Display) {
        _ = engine.perform(.place(.right))
        expectFrame("first window right", first.id, Geometry.frame(for: .right, on: display))
        focus(second)
        _ = engine.perform(.place(.left))
        expectFrame("second window left", second.id, Geometry.frame(for: .left, on: display))
        _ = engine.perform(.focus(.right))
        report("focus the window on the right", wait { system.focusedWindow() == first.id } != nil,
               "focused \(String(describing: system.focusedWindow()))")
        engine.focused(first.id)
        _ = engine.previousWindow()
        report("tap goes back to the last window", wait { system.focusedWindow() == second.id } != nil,
               "focused \(String(describing: system.focusedWindow()))")
        engine.focused(second.id)
        if let number = engine.slots.numbers[first.id] {
            _ = engine.perform(.jump(number))
            report("jump to window \(number)", wait { system.focusedWindow() == first.id } != nil,
                   "focused \(String(describing: system.focusedWindow()))")
        } else {
            report("jump has a number", false, "no number for the first window")
        }
    }

    func restoreLayout(_ first: WindowInfo, on display: Display, original: CGRect) {
        engine.saveLayout()
        let scrambled = CGRect(x: display.visible.minX + 40, y: display.visible.minY + 40, width: 500, height: 300)
        system.apply([Move(window: first.id, start: Geometry.frame(for: .right, on: display), end: scrambled)])
        expectFrame("scramble a window", first.id, scrambled)
        let effect = engine.restoreLayout()
        report("restore names what it did", effect == .notice("Put 1 window back · ⇪ Z undoes", visible: true),
               "\(effect)")
        expectFrame("restore puts it back", first.id, Geometry.frame(for: .right, on: display))
        _ = engine.perform(.undo)
        expectFrame("undo the restore", first.id, scrambled)

        system.apply([Move(window: first.id, start: scrambled, end: original)])
        _ = wait(0.5) { false }
    }
}

let child = Process()
child.executableURL = URL(fileURLWithPath: arguments[0])
child.arguments = ["--windows", "2"]
try child.run()

// A running CatWM leaves the windows of a claimed process alone.
let claim = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/catwm/instances/minimalcat-check")
try? FileManager.default.createDirectory(at: claim, withIntermediateDirectories: true)
try? "\(ProcessInfo.processInfo.processIdentifier)\npids:\(child.processIdentifier)\n"
    .write(to: claim.appendingPathComponent("scope"), atomically: true, encoding: .utf8)

let failures = MainActor.assumeIsolated {
    let check = Check(scope: child.processIdentifier)
    check.run()
    return check.failures
}
child.terminate()
try? FileManager.default.removeItem(at: claim)
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
