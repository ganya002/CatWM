import AppKit
import ApplicationServices

// MARK: - Private symbols (looked up at runtime so a missing one degrades instead of failing to link)

private func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let p = dlsym(handle, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let axGetWindow: GetWindowFn? = symbol(
    "_AXUIElementGetWindow",
    in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")

enum Spaces {
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
    var frame: CGRect {
        guard let p = point(kAXPositionAttribute), let s = size(kAXSizeAttribute) else { return .null }
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
    }

    var frame: CGRect { element.frame }
    var isValid: Bool { element.string(kAXRoleAttribute) != nil }
    var isNativeFullscreen: Bool { element.bool("AXFullScreen") ?? false }

    func setPosition(_ p: CGPoint) {
        var p = p
        if let v = AXValueCreate(.cgPoint, &p) { element.set(kAXPositionAttribute, v) }
    }
    func setSize(_ s: CGSize) {
        var s = s
        if let v = AXValueCreate(.cgSize, &s) { element.set(kAXSizeAttribute, v) }
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
            AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        element.set(kAXMainAttribute, kCFBooleanTrue)
        element.perform(kAXRaiseAction)
    }

    func close() { element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction) }
}

/// Apps with AXEnhancedUserInterface on (set by VoiceOver, Magnet, Grammarly, ...) animate or
/// ignore frame changes. Turn it off while we move their windows, then restore it.
enum EnhancedUI {
    private static var held: [pid_t: (count: Int, wasOn: Bool)] = [:]
    private static let attr = "AXEnhancedUserInterface"

    static func suspend(_ pid: pid_t) {
        if let h = held[pid] { held[pid] = (h.count + 1, h.wasOn); return }
        let app = AXUIElementCreateApplication(pid)
        let on = app.bool(attr) ?? false
        if on { app.set(attr, kCFBooleanFalse) }
        held[pid] = (1, on)
    }
    static func resume(_ pid: pid_t) {
        guard let h = held[pid] else { return }
        if h.count > 1 { held[pid] = (h.count - 1, h.wasOn); return }
        held[pid] = nil
        if h.wasOn { AXUIElementCreateApplication(pid).set(attr, kCFBooleanTrue) }
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
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "\(id)"
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
            if alpha < 0.01 { continue } // invisible overlays
            if pid == Int(getpid()) {
                if layer == 0 { return nil } // over the Settings window: leave focus alone
                continue // the layout HUD
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
