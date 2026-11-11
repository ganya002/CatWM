import AppKit
import ApplicationServices
import ScreenCaptureKit
let startedAt = Date()
let budget = 15.0
let textEditID = "com.apple.TextEdit"
var displayCreatedAt: Date?
var cleaningUp = false
func ms(since date: Date = startedAt) -> Int { Int(Date().timeIntervalSince(date) * 1000) }
func remaining() -> Double { displayCreatedAt.map { budget - Date().timeIntervalSince($0) } ?? budget }
let logDirectory = "/tmp/agent-display-probe"
let logPath: String = {
    let format = DateFormatter()
    format.dateFormat = "yyyyMMdd-HHmmss"
    return "\(logDirectory)/run-\(format.string(from: Date())).log"
}()
do { try FileManager.default.createDirectory(atPath: logDirectory, withIntermediateDirectories: true) } catch {
    fatalError("Cannot create \(logDirectory)")
}
FileManager.default.createFile(atPath: logPath, contents: nil)
let logFile = FileHandle(forWritingAtPath: logPath)
func log(_ line: String) {
    print(line)
    fflush(stdout)
    logFile?.write(Data((line + "\n").utf8))
}
var table: [String] = []
func report(_ passed: Bool, _ step: String, _ began: Date, _ detail: String) {
    let line = "\(passed ? "PASS" : "FAIL") \(step) [\(ms(since: began)) ms] \(detail)"
    table.append(line)
    log(line)
}
func symbol<T>(_ name: String) -> T {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY) else {
        fatalError("Missing SkyLight framework")
    }
    guard let address = dlsym(handle, name) else { fatalError("Missing symbol: \(name)") }
    return unsafeBitCast(address, to: T.self)
}
let connection: @convention(c) () -> Int32 = symbol("SLSMainConnectionID")
let currentSpace: @convention(c) (Int32, CFString) -> UInt64 = symbol("SLSManagedDisplayGetCurrentSpace")
let cid = connection()
let mainUUID: CFString = {
    guard let uuid = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID())?.takeRetainedValue(),
          let text = CFUUIDCreateString(nil, uuid) else { fatalError("No main display UUID") }
    return text
}()
struct Snapshot: Equatable {
    var app: String?
    var space: UInt64
    var cursor: CGPoint
    var text: String { "frontmost=\(app ?? "nil") space=\(space) cursor=(\(Int(cursor.x)),\(Int(cursor.y)))" }
}
func snapshot() -> Snapshot {
    let front = NSWorkspace.shared.frontmostApplication
    return Snapshot(app: front?.bundleIdentifier ?? front?.localizedName, space: currentSpace(cid, mainUUID),
                    cursor: CGEvent(source: nil)?.location ?? .zero)
}
var baseline: Snapshot?
var lastSeen: Snapshot?
var changes: [String] = []
func observe() {
    guard baseline != nil else { return }
    let now = snapshot()
    guard now != lastSeen else { return }
    changes.append("+\(ms()) ms \(lastSeen?.text ?? "") -> \(now.text)")
    log("    raw change \(changes[changes.count - 1])")
    lastSeen = now
}
func poll(_ seconds: Double, interval: Double = 0.005, _ done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(cleaningUp ? seconds : min(seconds, remaining()))
    repeat {
        observe()
        if done() { return true }
        RunLoop.current.run(until: Date().addingTimeInterval(interval))
    } while Date() < deadline
    observe()
    return done()
}
final class Box<Value> { var value: Value? }
func blocking<Value>(_ seconds: Double, _ work: @escaping () async throws -> Value) -> Result<Value, Error>? {
    let box = Box<Result<Value, Error>>()
    let task = Task {
        do { box.value = .success(try await work()) } catch { box.value = .failure(error) }
    }
    _ = poll(seconds, interval: 0.002) { box.value != nil }
    if box.value == nil { task.cancel() }
    return box.value
}
enum ProbeError: Error { case missing(String) }
func within(_ step: String) -> Bool {
    guard remaining() > 0 else {
        report(false, step, Date(), "skipped: the \(Int(budget)) s display budget is spent")
        return false
    }
    return true
}
func isolation(_ step: String, since mark: Int, _ began: Date) {
    let clean = changes.count == mark
    report(clean, "\(step) isolation", began,
           clean ? "frontmost app, Space and cursor unchanged" : changes[mark...].joined(separator: "; "))
}
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var raw: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &raw) == .success ? raw : nil
}
func children(_ element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}
func find(_ root: AXUIElement, depth: Int = 6, _ match: @escaping (AXUIElement) -> Bool) -> AXUIElement? {
    if match(root) { return root }
    guard depth > 0 else { return nil }
    return children(root).lazy.compactMap { find($0, depth: depth - 1, match) }.first
}
func hasRole(_ role: String) -> (AXUIElement) -> Bool {
    { attribute($0, kAXRoleAttribute) as? String == role }
}
func windowInfos(of pid: pid_t) -> [[String: Any]] {
    let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return all.filter {
        $0[kCGWindowOwnerPID as String] as? pid_t == pid && $0[kCGWindowLayer as String] as? Int == 0
            && min(bounds(of: $0).width, bounds(of: $0).height) > 50
    }
}
func bounds(of info: [String: Any]) -> CGRect {
    guard let dictionary = info[kCGWindowBounds as String] as? [String: Any] else { return .zero }
    return CGRect(dictionaryRepresentation: dictionary as CFDictionary) ?? .zero
}
func activeDisplays() -> [CGDirectDisplayID] {
    var (ids, count) = ([CGDirectDisplayID](repeating: 0, count: 16), UInt32(0))
    CGGetActiveDisplayList(16, &ids, &count)
    return Array(ids.prefix(Int(count)))
}
var display: NSObject?
var displayID: CGDirectDisplayID = 0
var textEdit: NSRunningApplication?
var windowID: Int?
var axWindow: AXUIElement?
var firstSeen: Date?
typealias ObjectCall = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
typealias ModeCall = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> Unmanaged<AnyObject>?
typealias ApplyCall = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
func allocate(_ cls: AnyClass) -> AnyObject? {
    (cls as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
}
func implementation<T>(_ cls: AnyClass, _ name: String, as type: T.Type) -> (Selector, T)? {
    let selector = NSSelectorFromString(name)
    guard let imp = class_getMethodImplementation(cls, selector) else { return nil }
    return (selector, unsafeBitCast(imp, to: type))
}
func makeVirtualDisplay() -> NSObject? {
    guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
          let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
          let modeClass = NSClassFromString("CGVirtualDisplayMode"),
          let displayClass = NSClassFromString("CGVirtualDisplay"),
          let (modeSelector, modeInit) = implementation(modeClass, "initWithWidth:height:refreshRate:",
                                                        as: ModeCall.self),
          let (initSelector, displayInit) = implementation(displayClass, "initWithDescriptor:", as: ObjectCall.self),
          let (applySelector, apply) = implementation(displayClass, "applySettings:", as: ApplyCall.self),
          let rawMode = allocate(modeClass), let rawDisplay = allocate(displayClass),
          let mode = modeInit(rawMode, modeSelector, 1920, 1080, 60)?.takeRetainedValue()
    else { return nil }
    let descriptor = descriptorClass.init()
    descriptor.setValuesForKeys(["queue": DispatchQueue.main, "name": "CatWM agent probe", "maxPixelsWide": 1920,
                                 "maxPixelsHigh": 1080, "vendorID": 0x4341, "productID": 0x5701, "serialNum": 1,
                                 "sizeInMillimeters": NSValue(size: NSSize(width: 527, height: 296))])
    let settings = settingsClass.init()
    settings.setValuesForKeys(["hiDPI": 0, "modes": [mode]])
    guard let created = displayInit(rawDisplay, initSelector, descriptor)?.takeRetainedValue() as? NSObject,
          apply(created, applySelector, settings) else { return nil }
    return created
}
func preflight() {
    var missing: [String] = []
    if !AXIsProcessTrusted() { missing.append("Accessibility") }
    if !CGPreflightScreenCaptureAccess() { missing.append("Screen Recording") }
    if !missing.isEmpty {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
        for permission in missing {
            log("MISSING \(permission): grant it to \(binary) (macOS attributes the request to the app that "
                + "launched it, parent pid \(getppid())) in System Settings > Privacy & Security. Stopping.")
        }
        exit(3)
    }
    if !NSRunningApplication.runningApplications(withBundleIdentifier: textEditID).isEmpty {
        log("STOP: TextEdit is already running. Quit it first so the probe never touches your documents.")
        exit(3)
    }
}
func createDisplay() -> Bool {
    let began = Date()
    guard let created = makeVirtualDisplay(), let identifier = created.value(forKey: "displayID") as? UInt32 else {
        report(false, "1 create 1920x1080@60 virtual display", began, "private classes or the apply call failed")
        return false
    }
    (display, displayID, displayCreatedAt) = (created, identifier, Date())
    report(true, "1 create 1920x1080@60 virtual display", began, "CGDirectDisplayID=\(identifier)")
    return true
}
func confirmDisplay() {
    let began = Date()
    var listed: Int?
    _ = poll(3) {
        if listed == nil, activeDisplays().contains(displayID) { listed = ms(since: began) }
        return listed != nil
    }
    let bounds = CGDisplayBounds(displayID)
    report(listed != nil, "2a CGGetActiveDisplayList", began,
           listed.map { "listed after \($0) ms, bounds=\(bounds)" } ?? "never listed within 3 s")
    let shareableBegan = Date()
    var attempts = 0
    var lastError = "no error"
    var seen = false
    while !seen, remaining() > 0, ms(since: shareableBegan) < 3000 {
        attempts += 1
        switch blocking(2, { try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) }) {
        case .success(let content): seen = content.displays.contains { $0.displayID == displayID }
        case .failure(let error): lastError = "\(error)"
        case nil: lastError = "SCShareableContent timed out"
        }
        if !seen { _ = poll(0.1) { false } }
    }
    report(seen, "2b SCShareableContent", shareableBegan,
           seen ? "listed after \(attempts) attempt(s)" : "absent after \(attempts) attempt(s); \(lastError)")
}
func recordBaseline() {
    let began = Date()
    let start = snapshot()
    (baseline, lastSeen) = (start, start)
    report(start.space != 0, "3 baseline", began, start.text)
}
func launchTextEdit() -> Bool {
    let began = Date()
    let mark = changes.count
    guard within("4 launch TextEdit"),
          let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: textEditID) else { return false }
    let configuration = NSWorkspace.OpenConfiguration()
    (configuration.activates, configuration.hides, configuration.addsToRecentItems) = (false, false, false)
    configuration.arguments = ["-NSShowAppCentricOpenPanelInsteadOfUntitledFile", "NO"]
    let launched = Box<NSRunningApplication>()
    let failure = Box<String>()
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { app, error in
        launched.value = app
        failure.value = error.map { "\($0)" } ?? ""
    }
    var info: [String: Any]?
    _ = poll(4) {
        if let pid = launched.value?.processIdentifier { info = windowInfos(of: pid).first }
        return info != nil || failure.value?.isEmpty == false
    }
    textEdit = launched.value
    guard let found = info, let number = found[kCGWindowNumber as String] as? Int else {
        report(false, "4 launch TextEdit", began, "no window in 4 s; \(failure.value ?? "launch pending")")
        return false
    }
    (firstSeen, windowID) = (Date(), number)
    let onscreen = found[kCGWindowIsOnscreen as String] as? Bool ?? false
    report(true, "4 launch TextEdit", began, "pid=\(launched.value?.processIdentifier ?? 0) window=\(number) "
           + "first seen \(ms(since: began)) ms after launch request, bounds=\(bounds(of: found)) onscreen=\(onscreen)")
    log("    raw window \(found)")
    isolation("4", since: mark, began)
    return true
}
func moveWindow() {
    let began = Date()
    let mark = changes.count
    guard within("5 move to virtual display"), let pid = textEdit?.processIdentifier, let id = windowID,
          let seenAt = firstSeen else { return }
    let target = CGDisplayBounds(displayID)
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.5)
    var setError = AXError.cannotComplete
    _ = poll(2) {
        guard let window = (attribute(app, kAXWindowsAttribute) as? [AXUIElement])?.first else { return false }
        var origin = target.origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        axWindow = window
        setError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        return setError == .success
    }
    let setAt = ms(since: seenAt)
    var landed: CGRect = .zero
    let inside = poll(1.5) {
        landed = windowInfos(of: pid).first { $0[kCGWindowNumber as String] as? Int == id }.map(bounds) ?? .zero
        return !landed.isEmpty && target.contains(landed)
    }
    let exposure = ms(since: seenAt)
    report(inside, "5 move to virtual display", began,
           "AX set=\(setError.rawValue) at +\(setAt) ms; CG bounds \(landed) vs display \(target); "
           + "window existed \(exposure) ms (from first sighting, polled every ~5 ms) before it was inside")
    isolation("5", since: mark, began)
}
func hasVariation(_ image: CGImage) -> Bool {
    var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
    guard let context = CGContext(data: &pixels, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
    context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
    return Set(stride(from: 0, to: pixels.count, by: 4).map { Array(pixels[$0..<$0 + 4]) }).count > 1
}
func captureWindow() {
    let began = Date()
    guard within("6 capture one frame"), let id = windowID else { return }
    let result = blocking(5) { () async throws -> (CGImage, Int) in
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { Int($0.windowID) == id }) else {
            throw ProbeError.missing("window \(id) not in SCShareableContent")
        }
        let lookup = ms(since: began)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width)
        configuration.height = Int(window.frame.height)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        return (image, lookup)
    }
    switch result {
    case .success((let image, let lookup)):
        let variation = hasVariation(image)
        report(variation, "6 capture one frame", began, "image \(image.width)x\(image.height), lookup \(lookup) ms, "
               + "capture \(ms(since: began) - lookup) ms\(variation ? "" : ", but every sampled pixel is identical")")
    case .failure(let error): report(false, "6 capture one frame", began, "\(error)")
    case nil: report(false, "6 capture one frame", began, "timed out")
    }
}
func sendKey() {
    let began = Date()
    let mark = changes.count
    guard within("7 pid-targeted key"), let pid = textEdit?.processIdentifier, let window = axWindow,
          let area = find(window, hasRole(kAXTextAreaRole)) else {
        report(false, "7 pid-targeted key", began, "no TextEdit text area to read back")
        return
    }
    let before = attribute(area, kAXValueAttribute) as? String ?? ""
    let source = CGEventSource(stateID: .privateState)
    for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: Array("a".utf16))
        event?.postToPid(pid)
    }
    var after = before
    let arrived = poll(1.5) {
        after = attribute(area, kAXValueAttribute) as? String ?? ""
        return after.count > before.count
    }
    report(arrived, "7 pid-targeted key", began, "AX value '\(before)' -> '\(after)' after \(ms(since: began)) ms")
    isolation("7", since: mark, began)
}
func pressDiscardButton(in window: AXUIElement) {
    guard let sheet = find(window, hasRole(kAXSheetRole)),
          let button = find(sheet, { hasRole(kAXButtonRole)($0) && ["Delete", "Don't Save", "Don\u{2019}t Save"]
              .contains(attribute($0, kAXTitleAttribute) as? String ?? "") }) else { return }
    AXUIElementPerformAction(button, kAXPressAction as CFString)
}
func cleanUp() {
    cleaningUp = true
    let began = Date()
    if let pid = textEdit?.processIdentifier {
        if let window = axWindow, let close = attribute(window, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(unsafeBitCast(close, to: AXUIElement.self), kAXPressAction as CFString)
        }
        let closed = poll(3, interval: 0.05) {
            if let window = axWindow { pressDiscardButton(in: window) }
            return windowInfos(of: pid).isEmpty
        }
        report(closed, "8a close TextEdit window without saving", began, closed ? "no windows left" : "still open")
        let quitBegan = Date()
        textEdit?.terminate()
        var quit = poll(3, interval: 0.05) { textEdit?.isTerminated == true }
        if !quit { textEdit?.forceTerminate(); quit = poll(1, interval: 0.05) { textEdit?.isTerminated == true } }
        report(quit, "8b terminate TextEdit", quitBegan, "terminated=\(quit)")
    }
    let releaseBegan = Date()
    display = nil
    let gone = poll(3, interval: 0.02) { !activeDisplays().contains(displayID) }
    report(gone, "8c release virtual display", releaseBegan,
           "gone from CGGetActiveDisplayList=\(gone); alive \(displayCreatedAt.map { ms(since: $0) } ?? 0) ms")
}
NSApplication.shared.setActivationPolicy(.accessory)
log("AgentDisplayProbe log: \(logPath)")
preflight()
DispatchQueue.global().asyncAfter(deadline: .now() + budget + 12) {
    log("WATCHDOG: probe hung, terminating TextEdit and exiting so the display is released")
    textEdit?.terminate()
    exit(2)
}
guard createDisplay() else { exit(1) }
confirmDisplay()
recordBaseline()
if launchTextEdit() {
    moveWindow()
    captureWindow()
    sendKey()
}
cleanUp()
log("\n=== RESULT TABLE ===")
table.forEach { log($0) }
let allPassed = table.allSatisfy { $0.hasPrefix("PASS") }
log(allPassed ? "GO: every step passed" : "NO-GO: at least one step failed")
exit(allPassed ? 0 : 1)
