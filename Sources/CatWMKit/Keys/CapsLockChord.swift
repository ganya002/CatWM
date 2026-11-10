import AppKit
import IOKit
import IOKit.hid

package final class CapsLockChord {
    package static let shared = CapsLockChord()
    package static let keyCode: UInt16 = 57

    private var timer: Timer?
    private var ticks = 0
    private var terminateObserver: NSObjectProtocol?

    private init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.restore() }
    }

    private func tick() {
        if Permission.accessibility.isGranted, !rawActive { startRaw() }
        ticks += 1
        if ticks.isMultiple(of: 20) { refreshDelay() }
    }

    package static func isLocked(_ flags: CGEventFlags) -> Bool { flags.contains(.maskAlphaShift) }

    package private(set) var isBound = false

    package func setBound(_ bound: Bool) {
        let bound = bound && WindowManager.shared.input.capsLock
        guard bound != isBound else { return }
        isBound = bound
        Self.setDelay(bound ? 0 : -1)
    }

    private func refreshDelay() {
        if isBound { Self.setDelay(0) }
    }

    private static func setDelay(_ milliseconds: Int, wait: Bool = false) {
        let run = {
            Process.runTool("/usr/bin/hidutil", ["property",
                                                 "--matching", "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6}",
                                                 "--set", "{\"CapsLockDelayOverride\":\(milliseconds)}"])
        }
        if wait { run() } else { DispatchQueue.global(qos: .utility).async(execute: run) }
    }

    package func restore() {
        if isBound { Self.setDelay(-1, wait: true) }
    }

    private var hidManager: IOHIDManager?
    private var fired = false
    private var held = false
    private var upAt: TimeInterval = 0
    private var slowAt: TimeInterval = 0
    private var lockBefore = false
    private var restoreAt: TimeInterval = 0

    package var rawActive: Bool { hidManager != nil }

    private let grantedAtLaunch = PermissionWatcher.shared.atLaunch.contains(.inputMonitoring)
    private var rawMisses = 0

    package func start() {
        startRaw()
        refreshDelay()
    }

    private func startRaw() {
        guard hidManager == nil, Permission.inputMonitoring.isGranted else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                                kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == UInt32(kHIDPage_KeyboardOrKeypad),
                  IOHIDElementGetUsage(element) == UInt32(kHIDUsage_KeyboardCapsLock) else { return }
            if IOHIDValueGetIntegerValue(value) == 1 {
                CapsLockChord.shared.rawDown()
            } else {
                CapsLockChord.shared.rawUp()
            }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        if IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess {
            hidManager = manager
        } else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }

    package func stop() {
        guard let hidManager else { return }
        IOHIDManagerRegisterInputValueCallback(hidManager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = nil
    }

    private func rawListenerMissed() {
        guard hidManager != nil else { return }
        rawMisses += 1
        if rawMisses == 1 {
            stop()
            startRaw()
        } else if rawMisses == 2, !grantedAtLaunch {
            Log.info("Input Monitoring granted but no events: relaunching")
            Process.runTool("/bin/sh", ["-c", "sleep 0.7; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath],
                            wait: false)
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

    package func isEcho(lockNow: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - restoreAt < 0.3, lockNow == lockBefore { return true }
        guard fired else { return false }
        if hidManager != nil { return held || now - upAt < 1.5 }
        return false
    }

    package func slowPathFired(lockNow: Bool) {
        rawListenerMissed()
        fired = true
        lockBefore = !lockNow
        slowAt = ProcessInfo.processInfo.systemUptime
        restoreLock(lockNow)
    }

    package func restoreLock(_ lockNow: Bool) {
        guard lockNow != lockBefore else { return }
        let want = lockBefore
        restoreAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { Self.setLock(want) }
    }

    package static func setLock(_ locked: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else {
            return
        }
        defer { IOServiceClose(conn) }
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), locked)
    }
}
