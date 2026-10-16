// Tiling: Accessibility and private-API wrappers (Window, Screen, Spaces, CGWindowInfo).
import AppKit
import ApplicationServices

// MARK: - Private symbols (looked up at runtime so a missing one degrades instead of failing to link)

func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axGetWindow: GetWindowFn? = symbol(
    "_AXUIElementGetWindow",
    in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")

enum Spaces {
    /// This asynchronous bridge works for foreign windows on macOS 27 where the older
    /// move/compat APIs are refused. Never treat the issued request as a successful move.
    static var canMoveWindows: Bool {
        _ = conn?() // load SkyLight before resolving its internal operation
        return NativeSpaceMove.isAvailable
    }

    static func move(window id: CGWindowID, to target: UInt64, waitUntilOnScreen: Bool = false,
                     completion: @escaping (Bool) -> Void) {
        guard target != 0, canMoveWindows else { completion(false); return }
        if of(window: id) == [target] { completion(true); return }
        guard NativeSpaceMove.move(window: id, to: target) else { completion(false); return }
        let deadline = Date().addingTimeInterval(0.5)
        func check() {
            if of(window: id) == [target] {
                // Membership can update before the imported window joins the visible window
                // list. Committing then produces one layout without it and a second with it.
                let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
                if !waitUntilOnScreen || info?.first?[kCGWindowIsOnscreen as String] as? Bool == true {
                    completion(true)
                    return
                }
            }
            guard Date() < deadline else { completion(false); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01, execute: check)
        }
        check()
    }

    private typealias ConnFn = @convention(c) () -> Int32
    private typealias SpaceFn = @convention(c) (Int32, CFString) -> UInt64
    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
    private static let space: SpaceFn? = symbol("SLSManagedDisplayGetCurrentSpace", in: skylight)

    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private static let copySpaces: CopySpacesFn? = symbol("SLSCopyManagedDisplaySpaces", in: skylight)

    struct DisplaySpaces {
        let ids: [UInt64]     // every space on the display, left to right
        let desktops: [Int]   // indices into `ids` of normal desktops (not fullscreen apps)
        let current: Int?     // index into `ids`
    }

    /// The spaces on a display, in Mission Control order.
    static func list(display uuid: String) -> DisplaySpaces? {
        guard let conn, let copySpaces, let arr = copySpaces(conn())?.takeRetainedValue() as? [[String: Any]] else { return nil }
        let entry = arr.first { ($0["Display Identifier"] as? String) == uuid } ?? (arr.count == 1 ? arr[0] : nil)
        guard let entry, let spaces = entry["Spaces"] as? [[String: Any]] else { return nil }
        let ids = spaces.map { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? 0 }
        let desktops = spaces.indices.filter { (spaces[$0]["type"] as? Int ?? 0) == 0 }
        let cur = ((entry["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? NSNumber)?.uint64Value
        return DisplaySpaces(ids: ids, desktops: desktops, current: cur.flatMap { ids.firstIndex(of: $0) })
    }

    /// Whether the display shows a fullscreen app's space instead of a desktop.
    static func isFullscreen(display uuid: String) -> Bool {
        guard let s = list(display: uuid), let cur = s.current else { return false }
        return !s.desktops.contains(cur)
    }

    private typealias WindowSpacesFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let windowSpaces: WindowSpacesFn? = symbol("SLSCopySpacesForWindows", in: skylight)

    /// The spaces a window is on; empty when unknown.
    static func of(window id: CGWindowID) -> [UInt64] {
        guard let conn, let windowSpaces,
              let arr = windowSpaces(conn(), 0x7, [NSNumber(value: id)] as CFArray)?.takeRetainedValue() as? [NSNumber]
        else { return [] }
        return arr.map(\.uint64Value)
    }

    /// Current space on a display, so layouts are remembered per space like Amethyst.
    static func current(display uuid: String) -> UInt64 {
        guard let conn, let space else { return 0 }
        return space(conn(), uuid as CFString)
    }
}

/// Focusing through the window server, like yabai. `NSRunningApplication.activate()` is often
/// ignored on macOS 14+ when the caller isn't the active app, so FFM and movefocus can't rely on it.
enum WindowServerFocus {
    private typealias PSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias FrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let psn: PSNFn? = symbol("GetProcessForPID",
        in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
    private static let front: FrontFn? = symbol("_SLPSSetFrontProcessWithOptions", in: skylight)
    private static let post: PostFn? = symbol("SLPSPostEventRecordTo", in: skylight)

    static var isAvailable: Bool { psn != nil && front != nil && post != nil }

    static func focus(pid: pid_t, window: CGWindowID) -> Bool {
        guard let psn, let front, let post else { return false }
        var p = ProcessSerialNumber()
        guard psn(pid, &p) == noErr else { return false }
        guard front(&p, window, 0x200) == .success else { return false } // kCPSUserGenerated
        // Two synthetic "make key window" records, the format the window server expects.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: window) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = post(&p, &bytes)
        bytes[0x08] = 0x02
        _ = post(&p, &bytes)
        return true
    }
}

// MARK: - AXUIElement helpers

extension AXUIElement {
    func value(_ attr: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attr as CFString, &v) == .success ? v : nil
    }
    func string(_ attr: String) -> String? { value(attr) as? String }
    func bool(_ attr: String) -> Bool? { (value(attr) as? NSNumber)?.boolValue }
    func element(_ attr: String) -> AXUIElement? {
        guard let v = value(attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }
    func elements(_ attr: String) -> [AXUIElement] { (value(attr) as? [AXUIElement]) ?? [] }

    func point(_ attr: String) -> CGPoint? {
        guard let v = value(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }
    func size(_ attr: String) -> CGSize? {
        guard let v = value(attr), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }
    /// `.null` when the app doesn't answer or reports something that isn't a real rect. Apps that
    /// are closing (kitty does this under load) can report infinite or NaN geometry, and every
    /// caller that treats `isNull` as "unknown" then ignores the window instead of tiling with it.
    var frame: CGRect {
        guard let p = point(kAXPositionAttribute), let s = size(kAXSizeAttribute),
              [p.x, p.y, s.width, s.height].allSatisfy(\.isFinite) else { return .null }
        return CGRect(origin: p, size: s)
    }

    @discardableResult
    func set(_ attr: String, _ v: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attr as CFString, v) == .success
    }
    func isSettable(_ attr: String) -> Bool {
        var b = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(self, attr as CFString, &b) == .success && b.boolValue
    }
    func perform(_ action: String) { AXUIElementPerformAction(self, action as CFString) }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let axGetWindow, axGetWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}

// MARK: - Window

final class Window {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    var autoFloating = false
    var userFloating: Bool?
    var naturalFrame = CGRect.null // size when first discovered, before we tiled it
    var isFloating: Bool { userFloating ?? autoFloating }

    init(id: CGWindowID, element: AXUIElement, pid: pid_t, bundleID: String?) {
        self.id = id; self.element = element; self.pid = pid; self.bundleID = bundleID
        // A hung app would hold its write queue for the default six seconds. Half a second is long enough
        // for a slow one; `verify` corrects a frame that was dropped.
        AXUIElementSetMessagingTimeout(element, 0.5)
    }

    // The frame last read from the app or written to it. Read and written from any thread.
    private let frameLock = NSLock()
    private var lastFrame = CGRect.null

    /// Asks the app. Also updates `cachedFrame` when the app answers.
    var frame: CGRect {
        let f = element.frame
        if !f.isNull { frameLock.withLock { lastFrame = f } }
        return f
    }
    /// The frame last read or written, without a call to the app. A scan reads it again on each
    /// refresh that discovers windows. Asks the app only when nothing is known yet.
    var cachedFrame: CGRect {
        let f = frameLock.withLock { lastFrame }
        return f.isNull ? frame : f
    }
    /// Sets the cached frame, for a window that a scan read off the main thread.
    func remember(_ f: CGRect) {
        if !f.isNull { frameLock.withLock { lastFrame = f } }
    }
    var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    var isNativeFullscreen: Bool { element.bool("AXFullScreen") ?? false }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p), element.set(kAXPositionAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.origin = p } }
        }
    }
    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s), element.set(kAXSizeAttribute, v) {
            frameLock.withLock { if !lastFrame.isNull { lastFrame.size = s } }
        }
    }
    /// Size → position → size. Setting position first lets macOS clamp a window that is still
    /// too big for its new spot (e.g. moving to a smaller display), which is a classic mis-tile.
    func setFrame(_ r: CGRect) {
        setSize(r.size)
        setPosition(r.origin)
        setSize(r.size)
    }

    func focus() {
        if !WindowServerFocus.focus(pid: pid, window: id) {
            axApp(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        element.set(kAXMainAttribute, kCFBooleanTrue)
        element.perform(kAXRaiseAction)
    }

    /// Presses the window's close button (looked for among its children when the app doesn't publish it as
    /// an attribute). Says what happened, for the log.
    @discardableResult
    func close() -> String {
        let button = element.element(kAXCloseButtonAttribute)
            ?? element.elements(kAXChildrenAttribute).first { $0.string(kAXSubroleAttribute) == kAXCloseButtonSubrole }
        guard let button else { return "no close button" }
        let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
        return result == .success ? "pressed" : "press failed (AX error \(result.rawValue))"
    }

    /// Chooses Close Window from the app's menu bar. Only for the app's focused window: the menu acts on that one.
    func closeFromMenu() -> Bool {
        let bar = axApp(pid).element(kAXMenuBarAttribute)
        for top in bar?.elements(kAXChildrenAttribute) ?? [] {
            for menu in top.elements(kAXChildrenAttribute) {
                for item in menu.elements(kAXChildrenAttribute) where ["Close Window", "Close"].contains(item.string(kAXTitleAttribute) ?? "") {
                    guard item.bool(kAXEnabledAttribute) != false else { continue }
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }
}

/// Apps with AXEnhancedUserInterface on (set by VoiceOver, Magnet, Grammarly, ...) animate or
/// ignore frame changes. Turn it off while we move their windows, then restore it.
/// Called from the main thread and from the animator's per-app queues, so each app has its own lock:
/// a slow app's AX call only ever waits on that same app.
enum EnhancedUI {
    private static var held: [pid_t: (count: Int, wasOn: Bool)] = [:]
    private static var locks: [pid_t: NSLock] = [:]
    private static let tableLock = NSLock() // guards `held` and `locks`
    private static let attr = "AXEnhancedUserInterface"

    static func suspend(_ pid: pid_t) {
        let l = lock(pid)
        l.lock(); defer { l.unlock() }
        if let h = tableLock.withLock({ held[pid] }) { tableLock.withLock { held[pid] = (h.count + 1, h.wasOn) }; return }
        let app = axApp(pid)
        let on = app.bool(attr) ?? false
        if on { app.set(attr, kCFBooleanFalse) }
        tableLock.withLock { held[pid] = (1, on) }
    }
    static func resume(_ pid: pid_t) {
        let l = lock(pid)
        l.lock(); defer { l.unlock() }
        guard let h = tableLock.withLock({ held[pid] }) else { return }
        if h.count > 1 { tableLock.withLock { held[pid] = (h.count - 1, h.wasOn) }; return }
        tableLock.withLock { held[pid] = nil }
        if h.wasOn { axApp(pid).set(attr, kCFBooleanTrue) }
    }

    private static func lock(_ pid: pid_t) -> NSLock {
        tableLock.withLock {
            if let l = locks[pid] { return l }
            let l = NSLock()
            locks[pid] = l
            return l
        }
    }
}

// MARK: - Screens & CG window list (all rects in top-left-origin "Quartz" coordinates, same as AX)

struct Screen {
    let id: CGDirectDisplayID
    let uuid: String
    let frame: CGRect
    let visible: CGRect
    let isBuiltin: Bool
    let ns: NSScreen

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    static func all() -> [Screen] {
        guard let primary = NSScreen.screens.first else { return [] }
        let h = primary.frame.height
        func flip(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height) }
        return NSScreen.screens.compactMap { s in
            guard let id = s.displayID else { return nil }
            let uuid = s.displayUUID ?? "\(id)"
            return Screen(id: id, uuid: uuid, frame: flip(s.frame), visible: flip(s.visibleFrame),
                          isBuiltin: CGDisplayIsBuiltin(id) != 0, ns: s)
        }
        .sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }
}

struct CGWindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let bounds: CGRect

    /// Normal-layer windows on screen right now, front to back. This is the source of truth for
    /// "what is on the current space", which AX alone can't answer reliably.
    static func onScreen() -> [CGWindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard (d[kCGWindowLayer as String] as? Int) == 0,
                  let n = d[kCGWindowNumber as String] as? Int,
                  let pid = d[kCGWindowOwnerPID as String] as? Int,
                  let b = d[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: b) else { return nil }
            return CGWindowInfo(id: CGWindowID(n), pid: pid_t(pid), bounds: bounds)
        }
    }
}

extension CGWindowInfo {
    /// The normal window under the point, or nil if a menu, the menu bar or the Dock is on top of it.
    static func normalWindow(at p: CGPoint) -> CGWindowInfo? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let blocking: Set<Int> = [Int(CGWindowLevelForKey(.dockWindow)), Int(CGWindowLevelForKey(.mainMenuWindow)),
                                  Int(CGWindowLevelForKey(.statusWindow)), Int(CGWindowLevelForKey(.popUpMenuWindow))]
        for d in list {
            guard let b = d[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: b),
                  bounds.contains(p), let pid = d[kCGWindowOwnerPID as String] as? Int, let n = d[kCGWindowNumber as String] as? Int
            else { continue }
            let layer = d[kCGWindowLayer as String] as? Int ?? 0
            let alpha = d[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.01 || FocusDim.shared.owns(n) { continue } // invisible overlays, the focus dim
            if pid == Int(getpid()) {
                // Over Settings, a menu or a card: leave focus alone. Overlays the mouse passes through
                // (the HUD, tooltips) don't count. Settings floats, so its layer doesn't tell.
                if NSApp.window(withWindowNumber: n)?.ignoresMouseEvents == false { return nil }
                continue
            }
            if layer == 0 { return CGWindowInfo(id: CGWindowID(n), pid: pid_t(pid), bounds: bounds) }
            if blocking.contains(layer) { return nil }
        }
        return nil
    }
}

func mouseLocation() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }

extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
    /// Round edges independently so neighbouring windows never get 1px gaps or overlaps.
    var pixelAligned: CGRect {
        let x0 = minX.rounded(), y0 = minY.rounded(), x1 = maxX.rounded(), y1 = maxY.rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
    func approxEqual(_ o: CGRect, tolerance t: CGFloat = 1.5) -> Bool {
        abs(minX - o.minX) <= t && abs(minY - o.minY) <= t && abs(width - o.width) <= t && abs(height - o.height) <= t
    }
}

/// macOS's own Mission Control shortcuts, read from the user's keyboard settings.
enum SystemShortcut {
    struct Combo { let keyCode: UInt16; let flags: CGEventFlags }

    private static func read(_ id: Int) -> (enabled: Bool, combo: Combo)? {
        guard let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys"),
              let entry = all[String(id)] as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? NSNumber)?.boolValue ?? false)
        guard let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber], params.count == 3 else { return nil }
        return (enabled, Combo(keyCode: params[1].uint16Value, flags: CGEventFlags(rawValue: params[2].uint64Value)))
    }

    /// "Switch to Desktop N", only when it's turned on.
    static func desktop(_ n: Int) -> Combo? {
        guard (1...16).contains(n), let s = read(117 + n), s.enabled else { return nil }
        return s.combo
    }

    /// "Move left/right a space". On by default (Ctrl-←/→), so missing entries fall back to that.
    static func step(right: Bool) -> Combo? {
        if let s = read(right ? 81 : 79) { return s.enabled ? s.combo : nil }
        return Combo(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
    }
}
