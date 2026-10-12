import AppKit
import IOKit
import IOKit.hid

/// Global keybinds via a CGEventTap. Carbon's RegisterEventHotKey can't be used: since macOS 15 it
/// rejects Option-only and Option+Shift combos, which are exactly the Hyprland/Amethyst-style binds.
final class Hotkeys {
    static let shared = Hotkeys()
    /// Marks events we synthesize ourselves (e.g. Ctrl-N for spaces) so we never match them.
    static let syntheticMarker: Int64 = 0x4859_5052

    var handler: ((KeyBinding) -> Void)?
    /// Set while the settings window records a shortcut, so the combo reaches it instead of firing.
    var paused = false
    private var tables: [String: [UInt64: KeyBinding]] = [:] // submap → combo → bind ("" = global)
    /// Active submap (mode); "" when none. Changed right inside the tap so the very next key
    /// is already matched against the new mode.
    private(set) var submap = ""
    var onSubmapChange: ((String) -> Void)?
    private var tap: CFMachPort?

    func setBindings(_ list: [KeyBinding]) {
        tables = [:]
        for b in list { tables[b.submap, default: [:]][Self.key(b.keyCode, b.mods)] = b }
        if !submap.isEmpty, tables[submap] == nil { setSubmap("") }
    }

    func setSubmap(_ name: String) {
        let n = name.lowercased() == "reset" ? "" : name
        guard n != submap else { return }
        submap = n
        DispatchQueue.main.async { [weak self] in self?.onSubmapChange?(n) }
    }

    enum Match { case bind(KeyBinding), swallow, pass }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// After permission comes back the old tap stays dead, so build a new one.
    func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        start()
    }

    fileprivate func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    /// Caps Lock arrives as flagsChanged (keycode 57), never keyDown. Swallowing the event isn't enough
    /// to keep the lock from toggling, so the lock state is put back through IOKit afterwards.
    static func setCapsLock(_ on: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(kIOHIDSystemClass))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &conn) == KERN_SUCCESS else { return }
        defer { IOServiceClose(conn) }
        IOHIDSetModifierLockState(conn, Int32(kIOHIDCapsLockState), on)
    }

    func match(_ event: CGEvent) -> Match {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let k = Self.key(code, event.flags)
        if !submap.isEmpty {
            if let b = tables[submap]?[k] ?? tables[""]?[k] { return repeatOK(b, event) ? .bind(b) : .swallow }
            // Like vim's normal mode: stray keys do nothing instead of typing into the app,
            // but ⌘/⌃ shortcuts (copy, paste…) still reach it.
            return event.flags.isDisjoint(with: [.maskCommand, .maskControl]) ? .swallow : .pass
        }
        return tables[""]?[k].map { repeatOK($0, event) ? .bind($0) : .swallow } ?? .pass
    }

    /// Only binde-style binds fire on key autorepeat.
    private func repeatOK(_ b: KeyBinding, _ event: CGEvent) -> Bool {
        b.repeats || event.getIntegerValueField(.keyboardEventAutorepeat) == 0
    }

    private static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }

    /// How synthetic shortcuts are posted. macOS only fires some system shortcuts (like switching
    /// spaces) when the event looks like a real key press, so the default wraps the key in real
    /// modifier key-downs and adds the Fn flag arrow keys carry. Selectable over IPC for diagnosis.
    enum PostStyle: Int { case plain = 0, arrowFlags = 1, physical = 2 }
    static var postStyle: PostStyle = .physical

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
        // Modifier keys (left variants) to hold around the key, outermost first.
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

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        Hotkeys.shared.reenable()
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    if type == .flagsChanged {
        // Only Caps Lock can be bound as a key; every other modifier change passes untouched.
        guard event.getIntegerValueField(.keyboardEventKeycode) == 57 else { return Unmanaged.passUnretained(event) }
    }
    let capsNow = event.flags.contains(.maskAlphaShift)
    let result = Hotkeys.shared.match(event)
    if type == .flagsChanged {
        guard case .bind = result else { return Unmanaged.passUnretained(event) }
        // Undo the toggle this press caused.
        DispatchQueue.main.async { Hotkeys.setCapsLock(!capsNow) }
    }
    switch result {
    case .pass:
        return Unmanaged.passUnretained(event)
    case .swallow:
        return nil
    case .bind(let b):
        if b.dispatcher == "submap" {
            Hotkeys.shared.setSubmap(b.arg)
        } else {
            // Return immediately so the tap never times out; do the (slow) AX work afterwards.
            DispatchQueue.main.async { Hotkeys.shared.handler?(b) }
        }
        return nil
    }
}
