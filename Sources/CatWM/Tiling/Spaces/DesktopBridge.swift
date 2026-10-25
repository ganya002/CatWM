import AppKit
import ObjectiveC

enum DesktopBridge {
    struct State {
        let transform: CGAffineTransform
        let options: UInt32
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

    static func create() -> UInt64? {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt32, CFDictionary
        ) -> UnsafeMutableRawPointer?
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt64
        guard lifecycleAvailable else { return nil }
        let result = NativeSpaceMove.performSynchronous(
            "SLSBridgedSpaceCreateOperation", selector: "initWithOptions:values:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, 0, [:] as CFDictionary)
        }
        let selector = NSSelectorFromString("spaceID")
        guard let result, let method = class_getInstanceMethod(object_getClass(result), selector) else { return nil }
        let space = unsafeBitCast(method_getImplementation(method), to: Read.self)(result, selector)
        return space == 0 ? nil : space
    }

    static func remove(_ space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, UInt64) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform("SLSBridgedSpaceDestroyOperation",
                                       selector: "initWithSpaceID:") { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space)
        }
    }

    static func move(_ space: UInt64, to display: String, index: Int32) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, UInt64, CFString, Int32
        ) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform(
            "SLSBridgedMoveManagedSpaceToDisplayIndexOperation", selector: "initWithSpaceID:displayIdentifier:index:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, space, display as CFString, index)
        }
    }

    static func attachMenuWindows(_ windows: [CGWindowID], to space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFArray, UInt64
        ) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform(
            "SLSBridgedMoveWindowsToManagedSpaceOperation", selector: "initWithWindows:spaceID:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, windows as CFArray, space)
        }
    }

    static func detachMenuWindows(_ windows: [CGWindowID], from space: UInt64) -> Bool {
        typealias Initialize = @convention(c) (
            UnsafeMutableRawPointer, Selector, CFArray, CFArray
        ) -> UnsafeMutableRawPointer?
        return NativeSpaceMove.perform(
            "SLSBridgedRemoveWindowsFromSpacesOperation", selector: "initWithWindows:spaces:"
        ) { object, selector, method in
            unsafeBitCast(method, to: Initialize.self)(object, selector, windows as CFArray, [space] as CFArray)
        }
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
