import AppKit
import Carbon.HIToolbox
import MinimalCatCore

/// Reads the cat key and its chords with one event tap. The cat key always arrives as F18: Caps Lock is mapped
/// onto F18 by `CapsMapping`, and under VoiceOver the real F18 is used.
@MainActor
public final class KeyTap {
    public static let catKeyCode = UInt16(kVK_F18)

    public var onOutput: ((CatKey.Output) -> Void)?
    public var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    private var machine = CatKey()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tick: Timer?
    private var swallowedUps: Set<UInt16> = []

    public init() {}

    @discardableResult
    public func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask), callback: keyTapCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        return true
    }

    public func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        tick?.invalidate()
        if machine.isHeld { machine = CatKey(); onOutput?(.hideOverlay) }
    }

    func reenable() { tap.map { CGEvent.tapEnable(tap: $0, enable: true) } }

    /// Returns true when the event is used and must not reach the app.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let now = ProcessInfo.processInfo.systemUptime
        if code == Self.catKeyCode {
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return true }
            if type == .keyDown {
                emit(machine.handle(.press(time: now)))
                tick?.invalidate()
                tick = Timer.scheduledTimer(withTimeInterval: CatKey.tapLimit, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.emit(self.machine.handle(.tick(time: ProcessInfo.processInfo.systemUptime)))
                    }
                }
            } else {
                tick?.invalidate()
                emit(machine.handle(.release(time: now)))
            }
            return true
        }
        if type == .keyUp { return swallowedUps.remove(code) != nil }
        guard let outputs = machine.handle(.key(code)) else { return false }
        swallowedUps.insert(code)
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { emit(outputs) }
        return true
    }

    private func emit(_ outputs: [CatKey.Output]?) {
        outputs?.forEach { onOutput?($0) }
    }
}

private func keyTapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                            refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tap.reenable()
            return Unmanaged.passUnretained(event)
        }
        return tap.handle(type, event) ? nil : Unmanaged.passUnretained(event)
    }
}
