// Keys: global key binds through a CGEventTap and modes (submaps). Caps Lock's part is in CapsLockChord.
import AppKit

/// Global keybinds via a CGEventTap. Carbon's RegisterEventHotKey can't be used: since macOS 15 it
/// rejects Option-only and Option+Shift combos, which are exactly the Hyprland/Amethyst-style binds.
final class Hotkeys {
    static let shared = Hotkeys()
    /// Marks events we synthesize ourselves (e.g. Ctrl-N for spaces) so we never match them.
    static let syntheticMarker: Int64 = 0x4859_5052

    var handler: ((KeyBinding) -> Void)?
    /// Posted on the main queue each time a bind fires, with the `KeyBinding` as `userInfo["bind"]`,
    /// so open views (the shortcut map) can flash its key.
    static let didFire = Notification.Name("OuchHotkeyDidFire")
    /// Set while the settings window records a shortcut, so the combo reaches it instead of firing.
    var paused = false
    private var tables: [String: [UInt64: KeyBinding]] = [:] // submap → combo → bind ("" = global)
    /// Active submap (mode); "" when none. Changed right inside the tap so the very next key
    /// is already matched against the new mode.
    private(set) var submap = ""
    var onSubmapChange: ((String) -> Void)?
    /// For the keyboard help: every modifier change and `?` pressed in a mode. Fired binds post `didFire`.
    var onFlagsChanged: ((CGEventFlags) -> Void)?
    var onHelpKey: (() -> Void)?
    /// Asked on a plain Return while set; true takes the key. The coach card never becomes key (focus
    /// stays on the practice windows), so this is how Return reaches its button.
    var onReturn: (() -> Bool)?
    /// Asked on Esc while set; true takes the key. The cursor quick-action menu closes on it and the mode stays.
    var onEscape: (() -> Bool)?
    /// Asked on a key while a mode is on, before that mode's binds. True takes the key. The cursor menu
    /// uses it so the shortcut drawn on a row runs that row.
    var onMenuKey: ((_ code: UInt16, _ flags: CGEventFlags, _ isRepeat: Bool) -> Bool)?
    /// A modifier tapped on its own in a mode (see `trackModifierTap`). Called on the main queue.
    var onModifierTap: (() -> Void)?
    /// The mode chord's modifiers (⌘ for ⌘⇪) while the keyboard help is up because they're held. Keys
    /// pressed then are matched as if those modifiers were up, so the mode's keys work under the help
    /// instead of reaching the app as ⌘ shortcuts.
    var heldChord: CGEventFlags = []
    private var tap: CFMachPort?
    private var swipeMonitor: Any?
    private var scrollAccum: [Int: Double] = [:] // axis → distance since the last fire
    private var lastScrollFire: [Int: TimeInterval] = [:]

    // MARK: - Bindings

    func setBindings(_ list: [KeyBinding]) {
        tables = [:]
        for b in list { tables[b.submap, default: [:]][Self.key(b.keyCode, b.mods)] = b }
        CapsLockChord.shared.setBound(list.contains { $0.keyCode == CapsLockChord.keyCode })
        if !submap.isEmpty, tables[submap] == nil { setSubmap("") }
    }

    func setSubmap(_ name: String) {
        let n = name.lowercased() == "reset" ? "" : name
        guard n != submap else { return }
        submap = n
        modeChord = n.isEmpty ? [] : CGEventSource.flagsState(.combinedSessionState).intersection(Self.tapMods).subtracting(.maskShift)
        tapDown = nil
        DispatchQueue.main.async { [weak self] in self?.onSubmapChange?(n) }
    }

    enum Match { case bind(KeyBinding), swallow, pass }

    // MARK: - Event tap

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: tapCallback, userInfo: nil) else { return false }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        startSwipes()
        CapsLockChord.shared.start()
        return true
    }

    // MARK: - Swipes, lookup and firing

    /// Trackpad swipes (`swipe_left` … `swipe_down`). Swipe events can't come through the tap, and a global
    /// monitor can't swallow them, so macOS's own gesture for the same swipe still happens unless it's off.
    private func startSwipes() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] e in
            guard let self, !paused else { return }
            // Cocoa reports a swipe left as deltaX +1 and a swipe up as deltaY +1.
            let code: UInt16
            if e.deltaX != 0 { code = e.deltaX > 0 ? SpecialKey.swipeLeft : SpecialKey.swipeRight }
            else if e.deltaY != 0 { code = e.deltaY > 0 ? SpecialKey.swipeUp : SpecialKey.swipeDown }
            else { return }
            let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
            if let b = lookup(code, flags) { fire(b) }
        }
    }

    private func lookup(_ code: UInt16, _ flags: CGEventFlags) -> KeyBinding? {
        let k = Self.key(code, flags)
        return (submap.isEmpty ? nil : tables[submap]?[k]) ?? tables[""]?[k]
    }

    /// The raw Caps Lock listener's key-down (see CapsLockChord): fires a Caps Lock bind for `flags`.
    /// Returns whether one fired.
    func fireCapsLock(_ flags: CGEventFlags) -> Bool {
        guard !paused, let b = lookup(CapsLockChord.keyCode, flags), repeatOK(b, nil) else { return false }
        fire(b)
        return true
    }

    fileprivate func fire(_ b: KeyBinding) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didFire, object: nil, userInfo: ["bind": b]) }
        if b.dispatcher == "submap" {
            setSubmap(b.arg)
        } else {
            // Return immediately so the tap never times out; do the (slow) AX work afterwards.
            DispatchQueue.main.async { [weak self] in self?.handler?(b) }
        }
    }

    /// Scroll wheel binds (`mouse_up`, `mouse_down`, `mouse_left`, `mouse_right`). Only scrolls with a
    /// matching bind are taken, so scrolling without those modifiers reaches the app as usual.
    /// Returns true if the event was used. A notched wheel fires once per notch; a trackpad fires
    /// once per `scrollStep` points, and its momentum tail is swallowed without firing.
    fileprivate func handleScroll(_ event: CGEvent) -> Bool {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dy = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let axis = abs(dy) >= abs(dx) ? 1 : 2
        let delta = axis == 1 ? dy : dx
        guard delta != 0 else { return false }
        // Positive vertical delta is a scroll up, positive horizontal a scroll left.
        let code = axis == 1 ? (delta > 0 ? SpecialKey.mouseUp : SpecialKey.mouseDown)
                             : (delta > 0 ? SpecialKey.mouseLeft : SpecialKey.mouseRight)
        guard let b = lookup(code, event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        if continuous {
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { scrollAccum[axis] = 0 } // began
            let acc = (scrollAccum[axis] ?? 0) * (delta > 0 ? 1 : -1) >= 0 ? (scrollAccum[axis] ?? 0) + delta : delta
            let now = ProcessInfo.processInfo.systemUptime
            guard abs(acc) >= Self.scrollStep, now - (lastScrollFire[axis] ?? 0) > 0.12 else { scrollAccum[axis] = acc; return true }
            scrollAccum[axis] = 0
            lastScrollFire[axis] = now
        }
        fire(b)
        return true
    }
    static let scrollStep = 40.0

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

    // MARK: - Modifier tap

    private static let tapMods: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    static let tapLimit = 0.35 // well under KeyHelp's 0.5s hold, so a tap never shows the help
    private var modeChord: CGEventFlags = [] // modifiers held when the mode began (⌘ for ⌘⇪)
    private var lastMods: CGEventFlags = []
    /// The modifier pressed alone in the mode, when, and the click count then. Cleared by anything else.
    fileprivate var tapDown: (flag: CGEventFlags, at: TimeInterval, clicks: UInt32)?

    /// A tap is `$mod` or the mode's chord modifier going down with nothing else held, while the mode is
    /// on, and up again within `tapLimit` with no key, click or other modifier between. The press must
    /// start in the mode: the ⌘ still held from ⌘⇪ was down before, so letting it go is not a tap.
    /// Only watches; the event always passes on.
    fileprivate func trackModifierTap(_ event: CGEvent) {
        let mods = event.flags.intersection(Self.tapMods)
        defer { lastMods = mods }
        guard onModifierTap != nil, !paused, !submap.isEmpty,
              event.getIntegerValueField(.keyboardEventKeycode) != Int64(CapsLockChord.keyCode),
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { tapDown = nil; return }
        if let down = tapDown {
            tapDown = nil
            if mods.isEmpty, ProcessInfo.processInfo.systemUptime - down.at < Self.tapLimit, Self.clicks() == down.clicks {
                DispatchQueue.main.async { [weak self] in self?.onModifierTap?() }
            }
            return
        }
        let allowed = WindowManager.shared.config.mainMod.union(modeChord)
        if lastMods.isEmpty, mods.rawValue.nonzeroBitCount == 1, allowed.contains(mods) {
            tapDown = (mods, ProcessInfo.processInfo.systemUptime, Self.clicks())
        }
    }

    /// Mouse buttons pressed so far this session. The tap doesn't see clicks, so a change means one came between.
    private static func clicks() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

    // MARK: - Matching

    func match(_ event: CGEvent) -> Match {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return .pass }
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
            // The chord held for keyboard help is not part of a window-mode shortcut, so a row's key
            // still matches while that chord is down.
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
            // Like vim's normal mode: stray keys do nothing instead of typing into the app,
            // but ⌘/⌃ shortcuts (copy, paste…) still reach it.
            return flags.isDisjoint(with: [.maskCommand, .maskControl]) ? .swallow : .pass
        }
        return tables[""]?[k].map { repeatOK($0, event) ? .bind($0) : .swallow } ?? .pass
    }

    /// What a key event types on the current layout, so `?` is found wherever the layout puts it.
    private static func typed(_ event: CGEvent) -> String {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }

    /// Only binde-style binds fire on key autorepeat.
    private func repeatOK(_ b: KeyBinding, _ event: CGEvent?) -> Bool {
        b.repeats || (event?.getIntegerValueField(.keyboardEventAutorepeat) ?? 0) == 0
    }

    private static func key(_ code: UInt16, _ flags: CGEventFlags) -> UInt64 {
        let mods = flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        return mods.rawValue | UInt64(code)
    }

    // MARK: - Posting keys

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

// MARK: - Tap callback

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
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
        // Only Caps Lock can be bound as a key; every other modifier change passes untouched.
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
        // Undo the toggle this press caused.
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
