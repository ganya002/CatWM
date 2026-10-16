import AppKit
import IOKit
import IOKit.hid

final class CapsLockChord {
    static let shared = CapsLockChord()
    static let keyCode: UInt16 = 57

    private var timer: Timer?
    private var ticks = 0

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                               queue: nil) { [weak self] _ in self?.restore() }
    }

    private func tick() {
        if Permission.accessibility.isGranted, !rawActive { startRaw() }
        ticks += 1
        if ticks % 20 == 0 { refreshDelay() }
    }

    static func isLocked(_ flags: CGEventFlags) -> Bool { flags.contains(.maskAlphaShift) }

    private(set) var isBound = false

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

    func restore() {
        if isBound { Self.setDelay(-1, wait: true) }
    }

    private var hidManager: IOHIDManager?
    private var fired = false
    private var held = false
    private var upAt: TimeInterval = 0
    private var slowAt: TimeInterval = 0
    private var lockBefore = false
    private var restoreAt: TimeInterval = 0

    var rawActive: Bool { hidManager != nil }

    private let grantedAtLaunch = PermissionWatcher.shared.atLaunch.contains(.inputMonitoring)
    private var rawMisses = 0

    func start() {
        startRaw()
        refreshDelay()
    }

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

    func isEcho(lockNow: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - restoreAt < 0.3, lockNow == lockBefore { return true }
        guard fired else { return false }
        if hidManager != nil { return held || now - upAt < 1.5 }
        return false
    }

    func slowPathFired(lockNow: Bool) {
        rawListenerMissed()
        fired = true
        lockBefore = !lockNow
        slowAt = ProcessInfo.processInfo.systemUptime
        restoreLock(lockNow)
    }

    func restoreLock(_ lockNow: Bool) {
        guard lockNow != lockBefore else { return }
        let want = lockBefore
        restoreAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { Self.setLock(want) }
    }

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
