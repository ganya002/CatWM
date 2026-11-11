import AppKit

extension Hotkeys {
    package func match(_ event: CGEvent) -> Match {
        guard !paused, !textInputActive,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let key = Self.key(code, event.flags)
        if code == 36 || code == 76, let onReturn,
           event.flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate, .maskShift]),
           event.getIntegerValueField(.keyboardEventAutorepeat) == 0, onReturn() {
            return .swallow
        }
        if code == 53, let onEscape, event.getIntegerValueField(.keyboardEventAutorepeat) == 0, onEscape() {
            return .swallow
        }
        if !submap.isEmpty {
            let flags = !heldChord.isEmpty && event.flags.contains(heldChord)
                ? event.flags.subtracting(heldChord) : event.flags
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if let onMenuKey, onMenuKey(code, flags, isRepeat) { return .swallow }
            if let bind = lookup(code, event.flags) { return repeatOK(bind, event) ? .bind(bind) : .swallow }
            if flags != event.flags, let bind = lookup(code, flags) {
                return repeatOK(bind, event) ? .bind(bind) : .swallow
            }
            if let help = onHelpKey, flags.isDisjoint(with: [.maskCommand, .maskControl]),
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
               Self.typed(event) == helpKey {
                DispatchQueue.main.async(execute: help)
                return .swallow
            }
            return flags.isDisjoint(with: [.maskCommand, .maskControl]) ? .swallow : .pass
        }
        return tables[""]?[key].map { repeatOK($0, event) ? .bind($0) : .swallow } ?? .pass
    }

    package static func typed(_ event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    package func repeatOK(_ bind: KeyBinding, _ event: CGEvent?) -> Bool {
        bind.repeats || (event?.getIntegerValueField(.keyboardEventAutorepeat) ?? 0) == 0
    }

    package nonisolated static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }

    package static func post(keyCode: UInt16, flags: CGEventFlags, style: PostStyle) {
        guard RealInput.allows("key \(keyCode)") else { return }
        var flags = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift,
                                        .maskSecondaryFn, .maskNumericPad])
        if style != .plain, (123...126).contains(keyCode) { flags.formUnion([.maskSecondaryFn, .maskNumericPad]) }
        let source = style == .physical ? CGEventSource(stateID: .hidSystemState) : nil
        func send(_ code: UInt16, _ down: Bool, _ eventFlags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = eventFlags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
            event.post(tap: .cghidEventTap)
        }
        let mods: [(CGEventFlags, UInt16)] = [(.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56),
                                              (.maskCommand, 55)]
            .filter { flags.contains($0.0) }
        var held: CGEventFlags = []
        if style == .physical {
            for (flag, code) in mods { held.insert(flag); send(code, true, held) }
        }
        send(keyCode, true, flags)
        send(keyCode, false, flags)
        if style == .physical {
            for (flag, code) in mods.reversed() { held.remove(flag); send(code, false, held) }
        }
    }
}

extension Hotkeys {
    package nonisolated static let windowMode = "window"

    package func handlePointer(_ type: CGEventType, _ event: CGEvent) -> Bool {
        type == .scrollWheel ? handleScroll(event) : handleRightClick(type, event)
    }

    private func handleRightClick(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .rightMouseUp {
            defer { swallowRightUp = false }
            return swallowRightUp
        }
        swallowRightUp = false
        guard submap == Self.windowMode, !paused, let onWindowModeClick else { return false }
        swallowRightUp = onWindowModeClick(event.location)
        return swallowRightUp
    }
}
