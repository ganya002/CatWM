import AppKit
import IOKit
import IOKit.hid

/// Global keybinds via a CGEventTap. Carbon's RegisterEventHotKey can't be used: since macOS 15 it
/// rejects Option-only and Option+Shift combos, which are exactly the Hyprland/Amethyst-style binds.
final class Hotkeys {
    static let shared = Hotkeys()
    /// Marks events we synthesize ourselves (e.g. Ctrl-N for spaces) so we never match them.
    static let syntheticMarker: Int64 = 0x4859_5052

    var handler: ((KeyBinding) -> Void)?
    /// Set while the settings window records a shortcut, so the combo reaches it instead of firing.
    var paused = false
    private var tables: [String: [UInt64: KeyBinding]] = [:] // submap → combo → bind ("" = global)
    /// Active submap (mode); "" when none. Changed right inside the tap so the very next key
    /// is already matched against the new mode.
    private(set) var submap = ""
    var onSubmapChange: ((String) -> Void)?
    private var tap: CFMachPort?
    private var swipeMonitor: Any?
    private var scrollAccum: [Int: Double] = [:] // axis → distance since the last fire
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

    /// macOS makes you hold Caps Lock a moment before it turns the lock *on* (turning it off is
    /// instant), and the raw HID report is held back the same way. That is why Super + Caps only felt
    /// instant while the lock was already on. The keyboards' delay override removes it, no permission
    /// needed. It lasts until the keyboard is unplugged or the Mac restarts, so it's re-applied now and
    /// then. Only on while a Caps Lock bind exists; -1 is "no override" and gives the normal behaviour back.
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

    /// Back to macOS's own Caps Lock behaviour (on quit).
    func restoreCapsLockDelay() {
        if capsBound { Self.setCapsLockDelay(-1, wait: true) }
    }

    /// Caps Lock is debounced by macOS: the key must be held a moment before a flagsChanged shows up,
    /// and a quick tap can be dropped. The keyboard's raw HID report has no such delay, so a listener
    /// (read-only, nothing is seized or remapped) fires the bind at the real key-down. The lock toggle
    /// macOS applies afterwards is then undone by the tap. Needs Input Monitoring; without it the
    /// flagsChanged path below still works, just slower.
    private var hidManager: IOHIDManager?
    private var rawCapsAt: TimeInterval = 0
    fileprivate var rawCapsLockState: Bool { rawCapsLock }
    private var rawCapsLock = false // lock state before the press

    var rawCapsActive: Bool { hidManager != nil }

    /// Whether Input Monitoring was already on when the app started (decides if a relaunch could help).
    private let grantedAtLaunch = Permissions.inputMonitoringGranted
    private var rawMisses = 0

    /// Safe to call repeatedly: the watchdog retries it until Input Monitoring has been granted.
    func startRawCaps() {
        guard hidManager == nil, Permissions.inputMonitoringGranted else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                          kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
            let el = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(el) == UInt32(kHIDUsage_KeyboardCapsLock),
                  IOHIDValueGetIntegerValue(value) == 1 else { return }
            Hotkeys.shared.rawCapsDown()
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

    /// A Caps Lock bind just fired through the slow path although the raw listener should have caught
    /// it first: macOS granted the permission but isn't delivering events to this process yet. First
    /// try a fresh listener; if that doesn't help and the grant came after launch, relaunch ourselves
    /// once (the new process starts with the permission in place), so the user never has to.
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
        guard !paused else { return }
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard let b = lookup(57, flags), repeatOK(b, nil) else { return }
        rawCapsAt = ProcessInfo.processInfo.systemUptime
        rawCapsLock = flags.contains(.maskAlphaShift)
        fire(b)
    }

    /// True if this Caps Lock flagsChanged is the delayed echo of a press already handled above.
    fileprivate func consumeRawCaps() -> Bool {
        let fresh = ProcessInfo.processInfo.systemUptime - rawCapsAt < 1.5
        rawCapsAt = 0
        return fresh
    }

    /// Trackpad swipes (`swipe_left` … `swipe_down`). Swipe events can't come through the tap, and a global
    /// monitor can't swallow them, so macOS's own gesture for the same swipe still happens unless it's off.
    private func startSwipes() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] e in
            guard let self, !paused else { return }
            // Cocoa reports a swipe left as deltaX +1 and a swipe up as deltaY +1.
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
        if b.dispatcher == "submap" {
            setSubmap(b.arg)
        } else {
            // Return immediately so the tap never times out; do the (slow) AX work afterwards.
            DispatchQueue.main.async { [weak self] in self?.handler?(b) }
        }
    }

    /// Scroll wheel binds (`mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`). Only scrolls with a
    /// matching bind are taken, so scrolling without those modifiers reaches the app as usual.
    /// Returns true if the event was used. A notched wheel fires once per notch; a trackpad fires
    /// once per `scrollStep` points, and its momentum tail is swallowed without firing.
    fileprivate func handleScroll(_ event: CGEvent) -> Bool {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dy = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let axis = abs(dy) >= abs(dx) ? 1 : 2
        let delta = axis == 1 ? dy : dx
        guard delta != 0 else { return false }
        // Positive vertical delta is a scroll up, positive horizontal a scroll left.
        let code = axis == 1 ? (delta > 0 ? SpecialKey.mouseUp : SpecialKey.mouseDown)
                             : (delta > 0 ? SpecialKey.mouseLeft : SpecialKey.mouseRight)
        guard let b = lookup(code, event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        if continuous {
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { scrollAccum[axis] = 0 } // began
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

    /// After permission comes back the old tap stays dead, so build a new one.
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

    /// Caps Lock arrives as flagsChanged (keycode 57), never keyDown. Swallowing the event isn't enough
    /// to keep the lock from toggling, so the lock state is put back through IOKit afterwards.
    static func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conn) }
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on)
    }

    func match(_ event: CGEvent) -> Match {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let k = Self.key(code, event.flags)
        if !submap.isEmpty {
            if let b = lookup(code, event.flags) { return repeatOK(b, event) ? .bind(b) : .swallow }
            // Like vim's normal mode: stray keys do nothing instead of typing into the app,
            // but ⌘/⌃ shortcuts (copy, paste…) still reach it.
            return event.flags.isDisjoint(with: [.maskCommand, .maskControl]) ? .swallow : .pass
        }
        return tables[""]?[k].map { repeatOK($0, event) ? .bind($0) : .swallow } ?? .pass
    }

    /// Only binde-style binds fire on key autorepeat.
    private func repeatOK(_ b: KeyBinding, _ event: CGEvent?) -> Bool {
        b.repeats || (event?.getIntegerValueField(.keyboardEventAutorepeat) ?? 0) == 0
    }

    private static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }

    /// How synthetic shortcuts are posted. macOS only fires some system shortcuts (like switching
    /// spaces) when the event looks like a real key press, so the default wraps the key in real
    /// modifier key-downs and adds the Fn flag arrow keys carry. Selectable over IPC for diagnosis.
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
        // Modifier keys (left variants) to hold around the key, outermost first.
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
    if type == .flagsChanged {
        // Only Caps Lock can be bound as a key; every other modifier change passes untouched.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 57 else { return Unmanaged.passUnretained(event) }
    }
    let capsNow = event.flags.contains(.maskAlphaShift)
    if type == .flagsChanged, Hotkeys.shared.consumeRawCaps() {
        let want = Hotkeys.shared.rawCapsLockState
        if capsNow != want { DispatchQueue.main.async { Hotkeys.setCapsLock(want) } }
        return nil
    }
    let result = Hotkeys.shared.match(event)
    if type == .flagsChanged {
        guard case .bind = result else { return Unmanaged.passUnretained(event) }
        Hotkeys.shared.rawListenerMissed()
        // Undo the toggle this press caused.
        DispatchQueue.main.async { Hotkeys.setCapsLock(!capsNow) }
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
