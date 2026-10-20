import AppKit
import ObjectiveC

enum DesktopBridge {
    struct State {
        let transform: CGAffineTransform
        let options: UInt32
    }

    static func state(_ space: UInt64) -> State? {
        typealias Connection = @convention(c) () -> Int32
        typealias Transform = @convention(c) (Int32, UInt64, UnsafeMutablePointer<UInt32>?) -> CGAffineTransform
        let handle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let connection = dlsym(handle, "SLSMainConnectionID"),
              let read = dlsym(handle, "SLSSpaceGetTransform") else { return nil }
        var options: UInt32 = 0
        let transform = unsafeBitCast(read, to: Transform.self)(
            unsafeBitCast(connection, to: Connection.self)(), space, &options)
        return State(transform: transform, options: options)
    }

    static func isIdentity(_ space: UInt64) -> Bool { state(space)?.transform == .identity }

    static func isIdle(display: String) -> Bool { NativeSpaceMove.isDisplayIdle(display) }

    static func transform(_ space: UInt64, x: CGFloat, options: UInt32 = 0) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt64, CGAffineTransform, UInt32
        ) -> UnsafeMutableRawPointer?
        let appliedOptions = x == 0 ? options : options & ~UInt32(0x0100_0000)
        return NativeSpaceMove.perform(
            "SLSBridgedSpaceSetTransformOperation", selector: "initWithSpaceID:transform:options:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space,
                                                      CGAffineTransform(translationX: x, y: 0), appliedOptions)
        }
    }

    static func animating(display: String, active: Bool) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFString, Bool
        ) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform(
            "SLSBridgedManagedDisplaySetIsAnimatingOperation", selector: "initWithDisplayIdentifier:isAnimating:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, display as CFString, active)
        }
    }

    static func willSwitch(_ spaces: [UInt64]) -> Bool {
        spacesOperation("SLSBridgedWillSwitchSpacesOperation", spaces)
    }

    static func setVisible(_ spaces: [UInt64], _ show: Bool) -> Bool {
        spacesOperation(show ? "SLSBridgedShowSpacesOperation" : "SLSBridgedHideSpacesOperation", spaces)
    }

    static func setCurrent(display: String, space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFString, UInt64
        ) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform("SLSBridgedManagedDisplaySetCurrentSpaceOperation",
                                       selector: "initWithDisplayIdentifier:spaceID:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, display as CFString, space)
        }
    }

    private static func spacesOperation(_ name: String, _ spaces: [UInt64]) -> Bool {
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, CFArray) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform(name, selector: "initWithSpaces:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, spaces as CFArray)
        }
    }
}
