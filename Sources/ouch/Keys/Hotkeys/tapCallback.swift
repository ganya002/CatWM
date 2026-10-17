import AppKit

func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
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
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(CapsLockChord.keyCode) else { return Unmanaged.passUnretained(event) }
    }
    let lockNow = CapsLockChord.isLocked(event.flags)
    if type == .flagsChanged, CapsLockChord.shared.isEcho(lockNow: lockNow) {
        CapsLockChord.shared.restoreLock(lockNow)
        return nil
    }
    let result = Hotkeys.shared.match(event)
    if type == .flagsChanged {
        guard case .bind = result else { return Unmanaged.passUnretained(event) }
        CapsLockChord.shared.slowPathFired(lockNow: lockNow)
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
