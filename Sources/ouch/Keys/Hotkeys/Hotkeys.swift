import AppKit

final class Hotkeys {

    static let shared = Hotkeys()
    static let syntheticMarker: Int64 = 0x4859_5052

    var handler: ((KeyBinding) -> Void)?
    static let didFire = Notification.Name("OuchHotkeyDidFire")
    var paused = false
    var textInputActive = false
    var tables: [String: [UInt64: KeyBinding]] = [:]
    var submap = ""
    var onSubmapChange: ((String) -> Void)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onHelpKey: (() -> Void)?
    var onReturn: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onMenuKey: ((_ code: UInt16, _ flags: CGEventFlags, _ isRepeat: Bool) -> Bool)?
    var onModifierTap: (() -> Void)?
    var heldChord: CGEventFlags = []
    var tap: CFMachPort?
    var swipeMonitor: Any?
    var scrollAccum: [Int: Double] = [:]
    var lastScrollFire: [Int: TimeInterval] = [:]

    enum Match { case bind(KeyBinding), swallow, pass }

    static let scrollStep = 40.0

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    static let tapMods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    static let tapLimit = 0.35
    var modeChord: CGEventFlags = []
    var lastMods: CGEventFlags = []
    var tapDown: (flag: CGEventFlags, at: TimeInterval, clicks: UInt32)?

    enum PostStyle: Int { case plain = 0, arrowFlags = 1, physical = 2 }
    static var postStyle: PostStyle = .physical

}
