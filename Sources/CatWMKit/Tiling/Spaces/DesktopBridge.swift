import AppKit
import ObjectiveC

package enum DesktopBridge {
    package struct State {
        package let transform: CGAffineTransform
        package let options: UInt32
    }

    private static func submit(
        _ name: String, selector: String,
        initialize: (UnsafeMutableRawPointer, Selector, IMP) -> UnsafeMutableRawPointer?
    ) -> Bool {
        RealInput.allows("Desktop operation \(name)")
            && NativeSpaceMove.perform(name, selector: selector, initialize: initialize)
    }

    private static func submitSynchronously(
        _ name: String, selector: String,
        initialize: (UnsafeMutableRawPointer, Selector, IMP) -> UnsafeMutableRawPointer?
    ) -> AnyObject? {
        RealInput.allows("Desktop operation \(name)")
            ? NativeSpaceMove.performSynchronous(name, selector: selector, initialize: initialize) : nil
    }

    private static let lifecycleAvailable: Bool = {
        guard NativeSpaceMove.isAvailable else { return false }
        return [
            ("SLSBridgedSpaceCreateOperation", "initWithOptions:values:"),
            ("SLSBridgedSpaceDestroyOperation", "initWithSpaceID:"),
            ("SLSBridgedMoveManagedSpaceToDisplayIndexOperation", "initWithSpaceID:displayIdentifier:index:")
        ].allSatisfy { name, selector in
            NSClassFromString(name).flatMap { class_getInstanceMethod($0, NSSelectorFromString(selector)) } != nil
        }
    }()

    package static func create() -> UInt64? {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt32, CFDictionary
        ) -> UnsafeMutableRawPointer?
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt64
        guard lifecycleAvailable else { return nil }
        let result = submitSynchronously(
            "SLSBridgedSpaceCreateOperation", selector: "initWithOptions:values:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, 0, [:] as CFDictionary)
        }
        let selector = NSSelectorFromString("spaceID")
        guard let result, let method = class_getInstanceMethod(object_getClass(result), selector) else { return nil }
        let space = unsafeBitCast(method_getImplementation(method), to: Read.self)(result, selector)
        return space == 0 ? nil : space
    }

    package static func remove(_ space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, UInt64) -> UnsafeMutableRawPointer?
        return submit("SLSBridgedSpaceDestroyOperation",
                                       selector: "initWithSpaceID:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space)
        }
    }

    package static func move(_ space: UInt64, to display: String, index: Int32) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt64, CFString, Int32
        ) -> UnsafeMutableRawPointer?
        return submit(
            "SLSBridgedMoveManagedSpaceToDisplayIndexOperation", selector: "initWithSpaceID:displayIdentifier:index:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space, display as CFString, index)
        }
    }

    package static func attachMenuWindows(_ windows: [CGWindowID], to space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFArray, UInt64
        ) -> UnsafeMutableRawPointer?
        return submit(
            "SLSBridgedMoveWindowsToManagedSpaceOperation", selector: "initWithWindows:spaceID:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, windows as CFArray, space)
        }
    }

    package static func detachMenuWindows(_ windows: [CGWindowID], from space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFArray, CFArray
        ) -> UnsafeMutableRawPointer?
        return submit(
            "SLSBridgedRemoveWindowsFromSpacesOperation", selector: "initWithWindows:spaces:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, windows as CFArray, [space] as CFArray)
        }
    }

    package static func state(_ space: UInt64) -> State? {
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

    package static func isIdentity(_ space: UInt64) -> Bool { state(space)?.transform == .identity }

    package static func isIdle(display: String) -> Bool { NativeSpaceMove.isDisplayIdle(display) }

    package static func transform(_ space: UInt64, x: CGFloat, options: UInt32 = 0) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt64, CGAffineTransform, UInt32
        ) -> UnsafeMutableRawPointer?
        let appliedOptions = x == 0 ? options : options & ~UInt32(0x0100_0000)
        return submit(
            "SLSBridgedSpaceSetTransformOperation", selector: "initWithSpaceID:transform:options:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space,
                                                      CGAffineTransform(translationX: x, y: 0), appliedOptions)
        }
    }

    package static func animating(display: String, active: Bool) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFString, Bool
        ) -> UnsafeMutableRawPointer?
        return submit(
            "SLSBridgedManagedDisplaySetIsAnimatingOperation", selector: "initWithDisplayIdentifier:isAnimating:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, display as CFString, active)
        }
    }

    package static func willSwitch(_ spaces: [UInt64]) -> Bool {
        spacesOperation("SLSBridgedWillSwitchSpacesOperation", spaces)
    }

    package static func setVisible(_ spaces: [UInt64], _ show: Bool) -> Bool {
        spacesOperation(show ? "SLSBridgedShowSpacesOperation" : "SLSBridgedHideSpacesOperation", spaces)
    }

    package static func setCurrent(display: String, space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFString, UInt64
        ) -> UnsafeMutableRawPointer?
        return submit("SLSBridgedManagedDisplaySetCurrentSpaceOperation",
                                       selector: "initWithDisplayIdentifier:spaceID:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, display as CFString, space)
        }
    }

    private static func spacesOperation(_ name: String, _ spaces: [UInt64]) -> Bool {
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, CFArray) -> UnsafeMutableRawPointer?
        return submit(name, selector: "initWithSpaces:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, spaces as CFArray)
        }
    }
}
