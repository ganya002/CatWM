import AppKit
import IOKit
import IOKit.hid

final class Hotkeys {
    static let shared = Hotkeys()
    static let syntheticMarker: Int64 = 0x4859_5052

    var handler: ((KeyBinding) -> Void)?
    static let didFire = Notification.Name("OuchHotkeyDidFire")
    var paused = false
    private var tables: [String: [UInt64: KeyBinding]] = [:]
    private(set) var submap = ""
    var onSubmapChange: ((String) -> Void)?
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onHelpKey: (() -> Void)?
    var onReturn: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onModifierTap: (() -> Void)?
    var heldChord: CGEventFlags = []
    private var tap: CFMachPort?
    private var swipeMonitor: Any?
    private var scrollAccum: [Int: Double] = [:]
    private var lastScrollFire: [Int: TimeInterval] = [:]


    func setBindings(_ list: [KeyBinding]) {
        tables = [:]
        for b in list { tables[b.submap, default: [:]][Self.key(b.keyCode, b.mods)] = b }
        let bound = list.contains { $0.keyCode == 57 }
        if bound != capsBound {
            capsBound = bound
            Self.setCapsLockDelay(bound ? 0 : -1)
        }
        if !submap.isEmpty, tables[submap] == nil { setSubmap("") }
    }

    func setSubmap(_ name: String) {
        let n = name.lowercased() == "reset" ? "" : name
        guard n != submap else { return }
        submap = n
        modeChord = n.isEmpty ? [] : CGEventSource.flagsState(.combinedSessionState).intersection(Self.tapMods).subtracting(.maskShift)
        tapDown = nil
        DispatchQueue.main.async { [weak self] in self?.onSubmapChange?(n) }
    }

    enum Match { case bind(KeyBinding), swallow, pass }


    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        startSwipes()
        startRawCaps()
        refreshCapsLockDelay()
        return true
    }

    private(set) var capsBound = false

    func refreshCapsLockDelay() {
        if capsBound { Self.setCapsLockDelay(0) }
    }

    private static func setCapsLockDelay(_ ms: Int, wait: Bool = false) {
        let run = {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
            p.arguments = ["property", "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}",
                           "--set", "{\"CapsLockDelayOverride\":\(ms)}"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        if wait { run() } else { DispatchQueue.global(qos: .utility).async(execute: run) }
    }

    func restoreCapsLockDelay() {
        if capsBound { Self.setCapsLockDelay(-1, wait: true) }
    }

    private var hidManager: IOHIDManager?
    private var capsFired = false
    private var capsHeld = false
    private var capsUpAt: TimeInterval = 0
    private var slowCapsAt: TimeInterval = 0
    private var capsLock = false
    private var restoreAt: TimeInterval = 0

    var rawCapsActive: Bool { hidManager != nil }

    private let grantedAtLaunch = Permissions.inputMonitoringGranted
    private var rawMisses = 0

    func startRawCaps() {
        guard hidManager == nil, Permissions.inputMonitoringGranted else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                          kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
            let el = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(el) == UInt32(kHIDUsage_KeyboardCapsLock) else { return }
            if IOHIDValueGetIntegerValue(value) == 1 { Hotkeys.shared.rawCapsDown() } else { Hotkeys.shared.rawCapsUp() }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            hidManager = m
        } else {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }

    private func stopRawCaps() {
        guard let m = hidManager else { return }
        IOHIDManagerRegisterInputValueCallback(m, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = nil
    }

    fileprivate func rawListenerMissed() {
        guard hidManager != nil else { return }
        rawMisses += 1
        if rawMisses == 1 {
            stopRawCaps()
            startRawCaps()
        } else if rawMisses == 2, !grantedAtLaunch {
            Log.info("Input Monitoring granted but no events: relaunching")
            let path = Bundle.main.bundlePath
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "sleep 0.7; /usr/bin/open -n \"$0\"", path]
            try? p.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func rawCapsDown() {
        capsHeld = true
        let now = ProcessInfo.processInfo.systemUptime
        if capsFired, now - slowCapsAt < 0.3 { slowCapsAt = 0; return }
        capsFired = false
        guard !paused else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard let b = lookup(57, flags), repeatOK(b, nil) else { return }
        capsFired = true
        capsLock = flags.contains(.maskAlphaShift)
        fire(b)
    }

    private func rawCapsUp() {
        capsHeld = false
        capsUpAt = ProcessInfo.processInfo.systemUptime
    }

    fileprivate func capsEcho(_ lockNow: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - restoreAt < 0.3, lockNow == capsLock { return true }
        guard capsFired else { return false }
        if hidManager != nil { return capsHeld || now - capsUpAt < 1.5 }
        return false
    }

    fileprivate func slowCapsFired(lockBefore: Bool) {
        capsFired = true
        capsLock = lockBefore
        slowCapsAt = ProcessInfo.processInfo.systemUptime
    }

    fileprivate func restoreCapsLock(_ lockNow: Bool) {
        guard lockNow != capsLock else { return }
        let want = capsLock
        restoreAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { Hotkeys.setCapsLock(want) }
    }


    private func startSwipes() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] e in
            guard let self, !paused else { return }
            let code: UInt16
            if e.deltaX != 0 { code = e.deltaX > 0 ? SpecialKey.swipeLeft : SpecialKey.swipeRight }
            else if e.deltaY != 0 { code = e.deltaY > 0 ? SpecialKey.swipeUp : SpecialKey.swipeDown }
            else { return }
            let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
            if let b = lookup(code, flags) { fire(b) }
        }
    }

    private func lookup(_ code: UInt16, _ flags: CGEventFlags) -> KeyBinding? {
        let k = Self.key(code, flags)
        return (submap.isEmpty ? nil : tables[submap]?[k]) ?? tables[""]?[k]
    }

    fileprivate func fire(_ b: KeyBinding) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didFire, object: nil, userInfo: ["bind": b]) }
        if b.dispatcher == "submap" {
            setSubmap(b.arg)
        } else {
            DispatchQueue.main.async { [weak self] in self?.handler?(b) }
        }
    }

    fileprivate func handleScroll(_ event: CGEvent) -> Bool {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dy = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let axis = abs(dy) >= abs(dx) ? 1 : 2
        let delta = axis == 1 ? dy : dx
        guard delta != 0 else { return false }
        let code = axis == 1 ? (delta > 0 ? SpecialKey.mouseUp : SpecialKey.mouseDown)
                             : (delta > 0 ? SpecialKey.mouseLeft : SpecialKey.mouseRight)
        guard let b = lookup(code, event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        if continuous {
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { scrollAccum[axis] = 0 }
            let acc = (scrollAccum[axis] ?? 0) * (delta > 0 ? 1 : -1) >= 0 ? (scrollAccum[axis] ?? 0) + delta : delta
            let now = ProcessInfo.processInfo.systemUptime
            guard abs(acc) >= Self.scrollStep, now - (lastScrollFire[axis] ?? 0) > 0.12 else { scrollAccum[axis] = acc; return true }
            scrollAccum[axis] = 0
            lastScrollFire[axis] = now
        }
        fire(b)
        return true
    }
    static let scrollStep = 40.0

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        start()
    }

    fileprivate func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    static func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conn) }
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on)
    }


    private static let tapMods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    static let tapLimit = 0.35
    private var modeChord: CGEventFlags = []
    private var lastMods: CGEventFlags = []
    fileprivate var tapDown: (flag: CGEventFlags, at: TimeInterval, clicks: UInt32)?

    fileprivate func trackModifierTap(_ event: CGEvent) {
        let mods = event.flags.intersection(Self.tapMods)
        defer { lastMods = mods }
        guard onModifierTap != nil, !paused, !submap.isEmpty,
              event.getIntegerValueField(.keyboardEventKeycode) != 57,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { tapDown = nil; return }
        if let down = tapDown {
            tapDown = nil
            if mods.isEmpty, ProcessInfo.processInfo.systemUptime - down.at < Self.tapLimit, Self.clicks() == down.clicks {
                DispatchQueue.main.async { [weak self] in self?.onModifierTap?() }
            }
            return
        }
        let allowed = WindowManager.shared.config.mainMod.union(modeChord)
        if lastMods.isEmpty, mods.rawValue.nonzeroBitCount == 1, allowed.contains(mods) {
            tapDown = (mods, ProcessInfo.processInfo.systemUptime, Self.clicks())
        }
    }

    private static func clicks() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }


    func match(_ event: CGEvent) -> Match {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let k = Self.key(code, event.flags)
        if code == 36 || code == 76, let onReturn,
           event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0, onReturn() {
            return .swallow
        }
        if code == 53, let onEscape, event.getIntegerValueField(.keyboardEventAutorepeat) == 0, onEscape() {
            return .swallow
        }
        if !submap.isEmpty {
            if let b = lookup(code, event.flags) { return repeatOK(b, event) ? .bind(b) : .swallow }
            let flags = !heldChord.isEmpty && event.flags.contains(heldChord) ? event.flags.subtracting(heldChord) : event.flags
            if flags != event.flags, let b = lookup(code, flags) { return repeatOK(b, event) ? .bind(b) : .swallow }
            if let help = onHelpKey, flags.isDisjoint(with: [.maskCommand, .maskControl]),
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0, Self.typed(event) == WindowManager.shared.config.keyboardHelpKey {
                DispatchQueue.main.async(execute: help)
                return .swallow
            }
            return flags.isDisjoint(with: [.maskCommand, .maskControl]) ? .swallow : .pass
        }
        return tables[""]?[k].map { repeatOK($0, event) ? .bind($0) : .swallow } ?? .pass
    }

    private static func typed(_ event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    private func repeatOK(_ b: KeyBinding, _ event: CGEvent?) -> Bool {
        b.repeats || (event?.getIntegerValueField(.keyboardEventAutorepeat) ?? 0) == 0
    }

    private static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }


    enum PostStyle: Int { case plain = 0, arrowFlags = 1, physical = 2 }
    static var postStyle: PostStyle = .physical

    static func post(keyCode: UInt16, flags: CGEventFlags, style: PostStyle? = nil) {
        let style = style ?? postStyle
        var flags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn, .maskNumericPad])
        if style != .plain, (123...126).contains(keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        let source = style == .physical ? CGEventSource(stateID: .hidSystemState) : nil
        func send(_ code: UInt16, _ down: Bool, _ f: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            e.flags = f
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            e.post(tap: .cghidEventTap)
        }
        let mods: [(CGEventFlags, UInt16)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55)]
            .filter { flags.contains($0.0) }
        var held: CGEventFlags = []
        if style == .physical {
            for (f, code) in mods { held.insert(f); send(code, true, held) }
        }
        send(keyCode, true, flags)
        send(keyCode, false, flags)
        if style == .physical {
            for (f, code) in mods.reversed() { held.remove(f); send(code, false, held) }
        }
    }
}


private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Hotkeys.shared.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type == .scrollWheel {
        return Hotkeys.shared.handleScroll(event) ? nil : Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    if type == .flagsChanged, let f = Hotkeys.shared.onFlagsChanged {
        let flags = event.flags
        DispatchQueue.main.async { f(flags) }
    }
    if type == .flagsChanged { Hotkeys.shared.trackModifierTap(event) } else { Hotkeys.shared.tapDown = nil }
    if type == .flagsChanged {
        guard event.getIntegerValueField(.keyboardEventKeycode) == 57 else { return Unmanaged.passUnretained(event) }
    }
    let capsNow = event.flags.contains(.maskAlphaShift)
    if type == .flagsChanged, Hotkeys.shared.capsEcho(capsNow) {
        Hotkeys.shared.restoreCapsLock(capsNow)
        return nil
    }
    let result = Hotkeys.shared.match(event)
    if type == .flagsChanged {
        guard case .bind = result else { return Unmanaged.passUnretained(event) }
        Hotkeys.shared.rawListenerMissed()
        Hotkeys.shared.slowCapsFired(lockBefore: !capsNow)
        Hotkeys.shared.restoreCapsLock(capsNow)
    }
    switch result {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .bind(let b):
        Hotkeys.shared.fire(b)
        return nil
    }
}
