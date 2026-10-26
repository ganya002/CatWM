import AppKit
import Carbon.HIToolbox
import MinimalCatCore

/// Reads the cat key, the right Command key, and its chords with one event tap. Only command keys are taken.
/// Every other key, such as Tab for Command-Tab, goes to the app as usual.
@MainActor
public final class KeyTap {
    public static let catKeyCode = UInt16(kVK_RightCommand)
    /// The device bit for the right Command key. `CGEventSource.keyState` does not report modifier keys.
    static let rightCommand: UInt64 = 0x10

    public var onOutput: ((CatKey.Output) -> Void)?
    /// True for a key that runs a command while the cat key is down.
    public var isCommand: (UInt16) -> Bool = { _ in false }
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
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
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
        swallowedUps = []
        reset()
    }

    private func reset() {
        tick?.invalidate()
        if machine.isHeld { machine = CatKey(); onOutput?(.hideOverlay) }
    }

    func reenable() { tap.map { CGEvent.tapEnable(tap: $0, enable: true) } }

    /// Returns true when the event is used and must not reach the app.
    func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let now = ProcessInfo.processInfo.systemUptime
        switch type {
        case .flagsChanged where code == Self.catKeyCode:
            if event.flags.rawValue & Self.rightCommand != 0 {
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
            return false
        case .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown:
            emit(machine.handle(.interrupt))
            return false
        case .keyUp:
            return swallowedUps.remove(code) != nil
        default:
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return swallowedUps.contains(code) }
            // A tap timeout or secure input can hide the release. The modifier state still knows.
            if machine.isHeld, CGEventSource.flagsState(.hidSystemState).rawValue & Self.rightCommand == 0 {
                reset()
            }
            guard machine.isHeld, isCommand(code) else {
                emit(machine.handle(.interrupt))
                return false
            }
            guard let outputs = machine.handle(.key(code)) else { return false }
            swallowedUps.insert(code)
            emit(outputs)
            return true
        }
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
