// Compile with NativeSpaceMove.swift and WindowServerUpdates.swift; see design/native-space-import.md.
// Only disposable child-process windows are moved. No Desktop is activated.
import AppKit

func symbol<T>(_ name: String) -> T {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)!
    guard let address = dlsym(handle, name) else { fatalError("Missing symbol: \(name)") }
    return unsafeBitCast(address, to: T.self)
}
let connection: @convention(c) () -> Int32 = symbol("SLSMainConnectionID")
let copyDisplays: @convention(c) (Int32) -> Unmanaged<CFArray>? = symbol("SLSCopyManagedDisplaySpaces")
let copyMembership: @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>? = symbol("SLSCopySpacesForWindows")
let moveOwned: @convention(c) (Int32, CFArray, UInt64) -> Void = symbol("SLSMoveWindowsToManagedSpace")
let cid = connection()
func membership(_ id: UInt32) -> [UInt64] {
    (copyMembership(cid, 7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber] ?? []).map(\.uint64Value)
}
func displays() -> [[String: Any]] {
    guard let result = copyDisplays(cid)?.takeRetainedValue() as? [[String: Any]] else {
        fatalError("No WindowServer connection. Run outside the sandbox in a logged-in GUI session.")
    }
    return result
}
func activeSpaces() -> [UInt64] {
    displays().compactMap { (($0["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value }
}
func wait(until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(1)
    repeat {
        if condition() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    } while Date() < deadline
    return condition()
}

if CommandLine.arguments.dropFirst().first == "--child" {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 180),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Ouch disposable Space probe"
    window.orderFrontRegardless()
    let id = UInt32(window.windowNumber), source = UInt64(CommandLine.arguments[2])!
    moveOwned(cid, [NSNumber(value: id)] as CFArray, source)
    guard wait(until: { membership(id) == [source] }) else { exit(1) }
    print(id); fflush(stdout)
    // Safety net if the parent exits unexpectedly.
    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { app.terminate(nil) }
    app.run()
    exit(0)
}

let initial = activeSpaces()
guard let display = displays().first,
      let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber,
      let spaces = display["Spaces"] as? [[String: Any]],
      let other = spaces.first(where: { ($0["type"] as? Int) == 0 && ($0["ManagedSpaceID"] as? NSNumber) != current })?["ManagedSpaceID"] as? NSNumber
else { fatalError("Create a second normal Desktop before running the probe.") }
guard NativeSpaceMove.isAvailable else { fatalError("Bridged move is unavailable on this macOS build.") }
var times: [Double] = []
let batchUpdates = CommandLine.arguments.contains("--batch-updates")
for attempt in 1...5 {
    let child = Process(), pipe = Pipe()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    child.arguments = ["--child", other.stringValue]
    child.standardOutput = pipe
    try child.run()
    defer { if child.isRunning { child.terminate() }; child.waitUntilExit() }
    let data = pipe.fileHandleForReading.availableData
    guard let text = String(data: data, encoding: .utf8), let id = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          membership(id) == [other.uint64Value] else { fatalError("Child setup failed") }
    let displayBatch = batchUpdates ? WindowServerUpdates.shared.begin() : nil
    if batchUpdates { precondition(displayBatch != nil, "WindowServer update batching unavailable") }
    let start = Date()
    guard NativeSpaceMove.move(window: id, to: current.uint64Value), wait(until: { membership(id) == [current.uint64Value] }) else {
        fatalError("Foreign-window import failed")
    }
    let elapsed = Date().timeIntervalSince(start) * 1000
    displayBatch?.finish()
    times.append(elapsed)
    guard activeSpaces() == initial else { fatalError("The active Desktop changed") }
    // Also verify a silent send to an inactive Desktop.
    guard NativeSpaceMove.move(window: id, to: other.uint64Value), wait(until: { membership(id) == [other.uint64Value] }), activeSpaces() == initial else {
        fatalError("Silent send failed")
    }
    print("\(attempt): imported in \(Int(elapsed)) ms; silent send passed; active Desktops unchanged")
}
print("PASS: 5 imports + 5 silent sends. Median import: \(Int(times.sorted()[2])) ms.")
