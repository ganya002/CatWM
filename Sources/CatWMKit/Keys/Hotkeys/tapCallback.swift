import AppKit
import Carbon.HIToolbox
@preconcurrency import CoreGraphics

package func tapCallback(proxy _: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let hotkeys = Unmanaged<Hotkeys>.fromOpaque(refcon).takeUnretainedValue()
    return onMainThread { hotkeys.swallows(type, event) } ? nil : Unmanaged.passUnretained(event)
}

extension Hotkeys {
    func swallows(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            return false
        }
        if type == .scrollWheel || type == .rightMouseDown || type == .rightMouseUp {
            return handlePointer(type, event)
        }
        guard type == .keyDown || type == .flagsChanged else { return false }
        if let intercept, intercept(type, event) { return true }
        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape),
           WindowManager.shared.cancelTabDrop() {
            return true
        }
        observe(type, event)
        if type == .flagsChanged {
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(CapsLockChord.keyCode) else {
                return false
            }
        }
        let lockNow = CapsLockChord.isLocked(event.flags)
        let chord = capsLockChord
        if type == .flagsChanged, chord?.isEcho(lockNow: lockNow) == true {
            chord?.restoreLock(lockNow)
            return true
        }
        let result = match(event)
        if type == .flagsChanged {
            guard case .bind = result else { return false }
            chord?.slowPathFired(lockNow: lockNow)
        }
        switch result {
        case .pass:
            return false
        case .swallow:
            return true
        case .bind(let bind):
            fire(bind)
            return true
        }
    }
}
