// Keys: Caps Lock as a bindable key (⌘⇪ enters window mode): raw HID listener, lock restore, delay override.
import AppKit
import IOKit
import IOKit.hid

/// Everything that makes a Caps Lock bind fire once, at once, and leave the lock as it was. Hotkeys
/// matches and fires the bind; this decides when, and cleans up after the press.
final class CapsLockChord {
    static let shared = CapsLockChord()
    /// Caps Lock's virtual keycode. It arrives as flagsChanged, never keyDown.
    static let keyCode: UInt16 = 57

    private var timer: Timer?
    private var ticks = 0

    private init() {
        // Retries the raw listener until Input Monitoring is granted, and re-applies the delay override.
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { [weak self] _ in self?.restore() }
    }

    private func tick() {
        if Permission.accessibility.isGranted, !rawActive { startRaw() }
        // Keyboards plugged in later start with macOS's Caps Lock delay again.
        ticks += 1
        if ticks % 20 == 0 { refreshDelay() }
    }

    /// The lock state an event (or the session's flags) carries.
    static func isLocked(_ flags: CGEventFlags) -> Bool { flags.contains(.maskAlphaShift) }

    // MARK: - Delay override

    /// macOS makes you hold Caps Lock a moment before it turns the lock *on* (turning it off is
    /// instant), and the raw HID report is held back the same way. That is why Super + Caps only felt
    /// instant while the lock was already on. The keyboards' delay override removes it, no permission
    /// needed. It lasts until the keyboard is unplugged or the Mac restarts, so it's re-applied now and
    /// then. Only on while a Caps Lock bind exists; -1 is "no override" and gives the normal behaviour back.
    private(set) var isBound = false

    /// Called with the new binds: whether any of them is on Caps Lock.
    func setBound(_ bound: Bool) {
        guard bound != isBound else { return }
        isBound = bound
        Self.setDelay(bound ? 0 : -1)
    }

    private func refreshDelay() {
        if isBound { Self.setDelay(0) }
    }

    private static func setDelay(_ ms: Int, wait: Bool = false) {
        let run = {
            Process.runTool("/usr/bin/hidutil", ["property", "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}",
                                                 "--set", "{\"CapsLockDelayOverride\":\(ms)}"])
        }
        if wait { run() } else { DispatchQueue.global(qos: .utility).async(execute: run) }
    }

    /// Back to macOS's own Caps Lock behaviour (on quit).
    func restore() {
        if isBound { Self.setDelay(-1, wait: true) }
    }

    // MARK: - Raw listener

    /// Caps Lock is debounced by macOS: the key must be held a moment before a flagsChanged shows up,
    /// and a quick tap can be dropped. The keyboard's raw HID report has no such delay, so a listener
    /// (read-only, nothing is seized or remapped) fires the bind at the real key-down. The lock toggle
    /// macOS applies afterwards is then undone by the tap. Needs Input Monitoring; without it the
    /// flagsChanged path in the tap still works, just slower.
    private var hidManager: IOHIDManager?
    /// One press fires a Caps Lock bind once. A long hold can bring more than one flagsChanged (the
    /// late toggle, our own restore); matching those again would run ⌘⇪'s exit bind right after the
    /// enter and leave the lock on. So every flagsChanged of a press that already fired is an echo.
    private var fired = false // a Caps Lock bind fired for the current press
    private var held = false // raw key state
    private var upAt: TimeInterval = 0
    private var slowAt: TimeInterval = 0 // the slow path fired before the raw report came
    private var lockBefore = false // lock state before the press, put back after it
    private var restoreAt: TimeInterval = 0

    var rawActive: Bool { hidManager != nil }

    /// Whether Input Monitoring was already on when the app started (decides if a relaunch could help).
    private let grantedAtLaunch = PermissionWatcher.shared.atLaunch.contains(.inputMonitoring)
    private var rawMisses = 0

    /// Starts the raw listener and the delay override, once the event tap is up.
    func start() {
        startRaw()
        refreshDelay()
    }

    /// Safe to call repeatedly: the timer retries it until Input Monitoring has been granted.
    private func startRaw() {
        guard hidManager == nil, Permission.inputMonitoring.isGranted else { return }
        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(m, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                          kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(m, { _, _, _, value in
            let el = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(el) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(el) == UInt32(kHIDUsage_KeyboardCapsLock) else { return }
            if IOHIDValueGetIntegerValue(value) == 1 { CapsLockChord.shared.rawDown() } else { CapsLockChord.shared.rawUp() }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            hidManager = m
        } else {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }

    func stop() {
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
    private func rawListenerMissed() {
        guard hidManager != nil else { return }
        rawMisses += 1
        if rawMisses == 1 {
            stop()
            startRaw()
        } else if rawMisses == 2, !grantedAtLaunch {
            Log.info("Input Monitoring granted but no events: relaunching")
            Process.runTool("/bin/sh", ["-c", "sleep 0.7; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath], wait: false)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func rawDown() {
        held = true
        let now = ProcessInfo.processInfo.systemUptime
        // The flagsChanged of this same press won the race and already fired the bind.
        if fired, now - slowAt < 0.3 { slowAt = 0; return }
        fired = false
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard Hotkeys.shared.fireCapsLock(flags) else { return }
        fired = true
        lockBefore = Self.isLocked(flags)
    }

    private func rawUp() {
        held = false
        upAt = ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Tap side

    /// True if this Caps Lock flagsChanged belongs to a press whose bind already fired, or is the
    /// echo of our own lock restore. Either way it must not be matched again.
    func isEcho(lockNow: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - restoreAt < 0.3, lockNow == lockBefore { return true }
        guard fired else { return false }
        if hidManager != nil { return held || now - upAt < 1.5 }
        return false
    }

    /// The slow path (the tap's flagsChanged) fired a Caps Lock bind for this press. Undoes the toggle
    /// this press caused.
    func slowPathFired(lockNow: Bool) {
        rawListenerMissed()
        fired = true
        lockBefore = !lockNow
        slowAt = ProcessInfo.processInfo.systemUptime
        restoreLock(lockNow)
    }

    /// Puts the lock back to how it was before the press, if the press changed it.
    func restoreLock(_ lockNow: Bool) {
        guard lockNow != lockBefore else { return }
        let want = lockBefore
        restoreAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { Self.setLock(want) }
    }

    /// Swallowing the Caps Lock event isn't enough to keep the lock from toggling, so the lock state is
    /// put back through IOKit afterwards.
    static func setLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conn) }
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on)
    }
}
