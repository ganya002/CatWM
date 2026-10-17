import AppKit
import ApplicationServices

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
        guard front(&p, window, 0x200) == .success else { return false }
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
