import AppKit

extension Hotkeys {
    func match(_ event: CGEvent) -> Match {
        guard !paused, !textInputActive, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
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
            let flags = !heldChord.isEmpty && event.flags.contains(heldChord) ? event.flags.subtracting(heldChord) : event.flags
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if let onMenuKey, onMenuKey(code, flags, isRepeat) { return .swallow }
            if let b = lookup(code, event.flags) { return repeatOK(b, event) ? .bind(b) : .swallow }
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

    static func typed(_ event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    func repeatOK(_ b: KeyBinding, _ event: CGEvent?) -> Bool {
        b.repeats || (event?.getIntegerValueField(.keyboardEventAutorepeat) ?? 0) == 0
    }

    static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }

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
