import AppKit

#if OUCH_ARRIVAL_PROBE
final class FocusDim {
    static let shared = FocusDim()
    func owns(_: Int) -> Bool { false }
}
#endif

func symbol<T>(_ name: String) -> T {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
        fatalError("Missing SkyLight framework")
    }
    guard let address = dlsym(handle, name) else { fatalError("Missing symbol: \(name)") }
    return unsafeBitCast(address, to: T.self)
}
let connection: @convention(c) () -> Int32 = symbol("SLSMainConnectionID")
let copyDisplays: @convention(c) (Int32) -> Unmanaged<CFArray>? = symbol("SLSCopyManagedDisplaySpaces")
let copyMembership: @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>? = symbol("SLSCopySpacesForWindows")
let moveOwned: @convention(c) (Int32, CFArray, UInt64) -> Void = symbol("SLSMoveWindowsToManagedSpace")
let cid = connection()
func membership(_ id: UInt32) -> [UInt64] {
    copyMembership(cid, 7, [id] as CFArray)?.takeRetainedValue() as? [UInt64] ?? []
}
func displays() -> [[String: Any]] {
    guard let result = copyDisplays(cid)?.takeRetainedValue() as? [[String: Any]] else {
        fatalError("No WindowServer connection. Run outside the sandbox in a logged-in GUI session.")
    }
    return result
}
func activeSpaces() -> [UInt64] {
    displays().compactMap { ($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64 }
}
func wait(until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(1)
    repeat {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    } while Date() < deadline
    return condition()
}

func move(window: CGWindowID, to destination: UInt64) -> Bool {
#if OUCH_ARRIVAL_PROBE
    let requireVisible = activeSpaces().contains(destination)
    var completed = false
    var succeeded = false
    Spaces.move(window: window, to: destination, waitUntilOnScreen: requireVisible) {
        succeeded = $0
        completed = true
    }
    guard wait(until: { completed }), succeeded else { return false }
    if requireVisible {
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, window) as? [[String: Any]]
        precondition(info?.first?[kCGWindowIsOnscreen as String] as? Bool == true,
                     "Completion preceded on-screen arrival")
    }
    return true
#else
    return NativeSpaceMove.move(window: window, to: destination)
#endif
}

if CommandLine.arguments.dropFirst().first == "--child" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Ouch disposable Space probe"
    window.orderFrontRegardless()
    let id = UInt32(window.windowNumber)
    guard let source = UInt64(CommandLine.arguments[2]) else { fatalError("Missing source Space") }
    moveOwned(cid, [id] as CFArray, source)
    guard wait(until: { membership(id) == [source] }) else { exit(1) }
    print(id); fflush(stdout)
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { app.terminate(nil) }
    app.run()
    exit(0)
}

let initial = activeSpaces()
guard let display = displays().first,
      let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? UInt64,
      let spaces = display["Spaces"] as? [[String: Any]],
      let otherSpace = spaces.first(where: {
          ($0["type"] as? Int) == 0 && ($0["ManagedSpaceID"] as? UInt64) != current
      }),
      let other = otherSpace["ManagedSpaceID"] as? UInt64
else { fatalError("Create a second normal Desktop before running the probe.") }
guard NativeSpaceMove.isAvailable else { fatalError("Bridged move is unavailable on this macOS build.") }
var times: [Double] = []
let batchUpdates = CommandLine.arguments.contains("--batch-updates")
for attempt in 1...5 {
    let child = Process(), pipe = Pipe()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    child.arguments = ["--child", String(other)]
    child.standardOutput = pipe
    try child.run()
    defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
    let data = pipe.fileHandleForReading.availableData
    guard let text = String(data: data, encoding: .utf8),
          let id = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          membership(id) == [other] else { fatalError("Child setup failed") }
    let displayBatch = batchUpdates ? WindowServerUpdates.shared.begin() : nil
    if batchUpdates { precondition(displayBatch != nil, "WindowServer update batching unavailable") }
    let start = Date()
    guard move(window: id, to: current), wait(until: { membership(id) == [current] }) else {
        fatalError("Foreign-window import failed")
    }
    let elapsed = Date().timeIntervalSince(start) * 1000
    displayBatch?.finish()
    times.append(elapsed)
    guard activeSpaces() == initial else { fatalError("The active Desktop changed") }
    guard move(window: id, to: other), wait(until: { membership(id) == [other] }),
          activeSpaces() == initial else {
        fatalError("Silent send failed")
    }
    print("\(attempt): imported in \(Int(elapsed)) ms; silent send passed; active Desktops unchanged")
}
print("PASS: 5 imports + 5 silent sends. Median import: \(Int(times.sorted()[2])) ms.")
