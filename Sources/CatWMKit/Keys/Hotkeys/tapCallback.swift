import AppKit
import Carbon.HIToolbox

package func tapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Hotkeys.shared.reenable()
        return Unmanaged.passUnretained(event)
    }
    if type == .scrollWheel || type == .rightMouseDown || type == .rightMouseUp {
        return Hotkeys.shared.handlePointer(type, event) ? nil : Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    if let intercept = Hotkeys.shared.intercept, intercept(type, event) { return nil }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape),
       WindowManager.shared.cancelTabDrop() {
        return nil
    }
    Hotkeys.shared.observe(type, event)
    if type == .flagsChanged {
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(CapsLockChord.keyCode) else {
            return Unmanaged.passUnretained(event)
        }
    }
    let lockNow = CapsLockChord.isLocked(event.flags)
    let chord = Hotkeys.shared.capsLockChord
    if type == .flagsChanged, chord?.isEcho(lockNow: lockNow) == true {
        chord?.restoreLock(lockNow)
        return nil
    }
    let result = Hotkeys.shared.match(event)
    if type == .flagsChanged {
        guard case .bind = result else { return Unmanaged.passUnretained(event) }
        chord?.slowPathFired(lockNow: lockNow)
    }
    switch result {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .bind(let bind):
        Hotkeys.shared.fire(bind)
        return nil
    }
}
