import AppKit
import ApplicationServices

func symbol<T>(_ name: String, in path: String? = nil) -> T? {
    guard let handle = dlopen(path, RTLD_LAZY), let address = dlsym(handle, name) else { return nil }
    return unsafeBitCast(address, to: T.self)
}

private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
private let getWindow: GetWindowFn? = symbol("_AXUIElementGetWindow")

extension AXUIElement {
    static func app(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return app
    }

    func value(_ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(self, attribute as CFString, &result) == .success ? result : nil
    }

    func string(_ attribute: String) -> String? { value(attribute) as? String }
    func flag(_ attribute: String) -> Bool { (value(attribute) as? Bool) ?? false }
    func elements(_ attribute: String) -> [AXUIElement] { (value(attribute) as? [AXUIElement]) ?? [] }

    func element(_ attribute: String) -> AXUIElement? {
        guard let result = value(attribute), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(result, to: AXUIElement.self)
    }

    var frame: CGRect? {
        var point = CGPoint.zero, size = CGSize.zero
        guard let position = value(kAXPositionAttribute), let extent = value(kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(extent, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    func setFrame(_ frame: CGRect) {
        var size = frame.size, origin = frame.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return
        }
        // Size, then position, then size again: a window clamped by the screen edge takes the full size on the
        // second write.
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, sizeValue)
    }

    func set(_ attribute: String, _ value: CFTypeRef) {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    var windowID: CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(self, &id) == .success, id != 0 else { return nil }
        return id
    }
}

/// Brings one window to the front, also when it belongs to another app.
enum WindowFocus {
    private typealias PSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias FrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32)
        -> CGError
    private typealias PostFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>)
        -> CGError
    private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
    private static let psn: PSNFn? = symbol("GetProcessForPID",
        in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
    private static let front: FrontFn? = symbol("_SLPSSetFrontProcessWithOptions", in: skylight)
    private static let post: PostFn? = symbol("SLPSPostEventRecordTo", in: skylight)

    static func focus(_ element: AXUIElement, id: CGWindowID, pid: pid_t) {
        if !frontWindowServer(pid: pid, window: id) {
            AXUIElement.app(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        element.set(kAXMainAttribute, kCFBooleanTrue)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// The same window-server call CatWM uses. It makes the window key without raising every window of the app.
    private static func frontWindowServer(pid: pid_t, window: CGWindowID) -> Bool {
        guard let psn, let front, let post else { return false }
        var process = ProcessSerialNumber()
        guard psn(pid, &process) == noErr, front(&process, window, 0x200) == .success else { return false }
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: window) { for (index, byte) in $0.enumerated() { bytes[0x3c + index] = byte } }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        bytes[0x08] = 0x01
        _ = post(&process, &bytes)
        bytes[0x08] = 0x02
        _ = post(&process, &bytes)
        return true
    }
}
