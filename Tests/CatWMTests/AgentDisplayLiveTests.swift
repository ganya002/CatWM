import AppKit
@testable import CatWMKit
import Testing

@MainActor final class LiveWatch {
    struct Snapshot: Equatable {
        var app: String?
        var space: UInt64
        var cursor: CGPoint
        var text: String { "frontmost=\(app ?? "nil") space=\(space) cursor=(\(Int(cursor.x)),\(Int(cursor.y)))" }
    }

    let started = Date()
    let display: AgentDisplay
    let users = NSScreen.userScreens.map { CGDisplayBounds($0.displayID ?? 0) }
    let mainUUID = NSScreen.screens.first?.displayUUID ?? ""
    var pid: pid_t?
    var samples = 0
    var changes: [String] = []
    var listedOnUsers: [String] = []
    var landedAt: Int?
    lazy var baseline = snapshot()
    lazy var last = baseline

    init(_ display: AgentDisplay) { self.display = display }

    func ms() -> Int { Int(Date().timeIntervalSince(started) * 1000) }

    func snapshot() -> Snapshot {
        Snapshot(app: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                 space: Spaces.current(display: mainUUID), cursor: mouseLocation())
    }

    func poll() {
        samples += 1
        let now = snapshot()
        if now != last { changes.append("+\(ms()) ms \(last.text) -> \(now.text)"); last = now }
        guard let pid else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list where info[kCGWindowOwnerPID as String] as? pid_t == pid
            && info[kCGWindowLayer as String] as? Int == 0 {
            let frame = (info[kCGWindowBounds as String] as? [String: Any])
                .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            guard frame.width > 50, frame.height > 50 else { continue }
            if users.contains(where: { $0.contains(frame.center) }) {
                listedOnUsers.append("+\(ms()) ms window \(info[kCGWindowNumber as String] ?? 0) \(frame)")
            }
            if display.bounds.contains(frame.center), landedAt == nil { landedAt = ms() }
        }
    }

    func spin(_ seconds: Double, every step: () -> Void = {}, until done: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            step()
            if done() { return true }
            await withCheckedContinuation { next in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.005) { next.resume() } // style-ok: samples a server
            }
        } while Date() < deadline
        return done()
    }

    func cli(_ arguments: [String]) -> String {
        guard let path = ProcessInfo.processInfo.environment["CATWM_CLI"] else { return "(no CATWM_CLI)" }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return "(cli failed to start)" }
        return String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

@MainActor @Suite(.enabled(if: ProcessInfo.processInfo.environment["CATWM_LIVE_AGENT_DISPLAY"] != nil))
struct AgentDisplayLiveTests {
    let editID = "com.apple.TextEdit"

    @Test func textEditLaunchedThroughTheAgentDisplayNeverReachesTheUsersDisplay() async throws {
        try #require(NSRunningApplication.runningApplications(withBundleIdentifier: editID).isEmpty,
                     "TextEdit already runs, so the check would touch its documents")
        let display = try #require(AgentDisplay())
        let watch = LiveWatch(display)
        print("LIVE display id=\(display.id) uuid=\(display.uuid) bounds=\(display.bounds) "
              + "created in \(watch.ms()) ms, owns=\(AgentDisplay.owns(display.id))")
        print("LIVE user displays=\(watch.users) NSScreens=\(NSScreen.screens.count)")
        #expect(NSScreen.screens.count == watch.users.count + 1)
        #expect(!Screen.all().contains { $0.id == display.id })
        print("LIVE catwm screens before launch: \(watch.cli(["screens", "--json"]))")

        print("LIVE baseline \(watch.baseline.text)")
        let launched = Task { @MainActor in
            let arguments = ["-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
            let pid = try? await display.launch(editID, arguments: arguments)
            print("LIVE launch returned pid \(pid.map(String.init) ?? "nil") at +\(watch.ms()) ms")
        }
        _ = await watch.spin(8, every: {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: editID)
            if watch.pid == nil, let app = running.first {
                watch.pid = app.processIdentifier
                print("LIVE TextEdit pid \(app.processIdentifier) seen at +\(watch.ms()) ms")
            }
            watch.poll()
        }, until: { watch.landedAt != nil })
        _ = await watch.spin(0.5, every: watch.poll, until: { false })
        report(watch)

        let app = watch.pid.flatMap { NSRunningApplication(processIdentifier: $0) }
        app?.terminate()
        if await !watch.spin(3, until: { app?.isTerminated ?? true }) { app?.forceTerminate() }
        _ = await watch.spin(1, until: { app?.isTerminated ?? true })
        _ = launched
        #expect(await release(display, watch))
    }

    func report(_ watch: LiveWatch) {
        print("LIVE window on agent display at +\(watch.landedAt ?? -1) ms; \(watch.samples) polls every ~5 ms")
        print("LIVE polls listing a TextEdit window on a user display: \(watch.listedOnUsers.count) "
              + "\(watch.listedOnUsers)")
        print("LIVE frontmost/space/cursor changes: \(watch.changes.count) \(watch.changes)")
        print("LIVE claimed pids: \(watch.display.pids)")
        print("LIVE catwm screens while the display is up: \(watch.cli(["screens", "--json"]))")
        print("LIVE catwm windows while the window is up: \(watch.cli(["windows", "--json"]))")
        #expect(watch.landedAt != nil)
        #expect(watch.changes.isEmpty)
    }

    func release(_ display: AgentDisplay, _ watch: LiveWatch) async -> Bool {
        let id = display.id
        let claim = Instance.paths.instancesFolder.appendingPathComponent("agent-\(id)/scope").path
        display.close()
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        let released = await watch.spin(3, until: {
            CGGetActiveDisplayList(16, &ids, &count)
            return !ids.prefix(Int(count)).contains(id)
        })
        print("LIVE released display: \(released), alive \(watch.ms()) ms, claim file gone: "
              + "\(!FileManager.default.fileExists(atPath: claim))")
        return released
    }
}
