import AppKit

package final class Hotkeys {
    package static let shared = Hotkeys()
    package static let syntheticMarker: Int64 = 0x4859_5052

    package var handler: ((KeyBinding) -> Void)?
    package static let didFire = Notification.Name("OuchHotkeyDidFire")
    package var paused = false
    package var textInputActive = false
    package var tables: [String: [UInt64: KeyBinding]] = [:]
    package var submap = ""
    package var onSubmapChange: ((String) -> Void)?
    package var onWindowModeClick: ((CGPoint) -> Bool)?
    package var onFlagsChanged: ((CGEventFlags) -> Void)?
    package var onHelpKey: (() -> Void)?
    package var onReturn: (() -> Bool)?
    package var onEscape: (() -> Bool)?
    package var onMenuKey: ((_ code: UInt16, _ flags: CGEventFlags, _ isRepeat: Bool) -> Bool)?
    package var onModifierTap: (() -> Void)?
    package var intercept: ((CGEventType, CGEvent) -> Bool)?
    package var heldChord: CGEventFlags = []
    package var tap: CFMachPort?
    package var capsLock = false
    package var capsLockChord: CapsLockChord? { capsLock ? .shared : nil }
    package var swipeMonitor: Any?
    package var scrollAccum: [Int: Double] = [:]
    package var lastScrollFire: [Int: TimeInterval] = [:]

    package enum Match { case bind(KeyBinding), swallow, pass }

    package static let scrollStep = 40.0

    package var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    package static let tapMods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    package static let tapLimit = 0.35
    package var modeChord: CGEventFlags = []
    package var lastMods: CGEventFlags = []
    package var tapDown: TapDown?
    package var swallowRightUp = false

    package struct TapDown {
        package let flag: CGEventFlags
        package let time: TimeInterval
        package let clicks: UInt32
    }

    package enum PostStyle: Int { case plain = 0, arrowFlags = 1, physical = 2 }
}
