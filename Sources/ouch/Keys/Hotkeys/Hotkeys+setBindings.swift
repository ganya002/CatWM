import AppKit

extension Hotkeys {
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

    func startSwipes() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] e in
            guard let self, !paused else { return }
            let code: UInt16
            if e.deltaX != 0 { code = e.deltaX > 0 ? SpecialKey.swipeLeft : SpecialKey.swipeRight }
            else if e.deltaY != 0 { code = e.deltaY > 0 ? SpecialKey.swipeUp : SpecialKey.swipeDown }
            else { return }
            let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
            if let b = lookup(code, flags) { fire(b) }
        }
    }

    func lookup(_ code: UInt16, _ flags: CGEventFlags) -> KeyBinding? {
        let k = Self.key(code, flags)
        return (submap.isEmpty ? nil : tables[submap]?[k]) ?? tables[""]?[k]
    }

    func fireCapsLock(_ flags: CGEventFlags) -> Bool {
        guard !paused, let b = lookup(CapsLockChord.keyCode, flags), repeatOK(b, nil) else { return false }
        fire(b)
        return true
    }

    func fire(_ b: KeyBinding) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didFire, object: nil, userInfo: ["bind": b]) }
        if b.dispatcher == "submap" {
            setSubmap(b.arg)
        } else {
            DispatchQueue.main.async { [weak self] in self?.handler?(b) }
        }
    }

    func handleScroll(_ event: CGEvent) -> Bool {
        guard !paused, event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dy = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) : event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let dx = continuous ? event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2) : event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let axis = abs(dy) >= abs(dx) ? 1 : 2
        let delta = axis == 1 ? dy : dx
        guard delta != 0 else { return false }
        let code = axis == 1 ? (delta > 0 ? SpecialKey.mouseUp : SpecialKey.mouseDown)
                             : (delta > 0 ? SpecialKey.mouseLeft : SpecialKey.mouseRight)
        guard let b = lookup(code, event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        if continuous {
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { scrollAccum[axis] = 0 }
            let acc = (scrollAccum[axis] ?? 0) * (delta > 0 ? 1 : -1) >= 0 ? (scrollAccum[axis] ?? 0) + delta : delta
            let now = ProcessInfo.processInfo.systemUptime
            guard abs(acc) >= Self.scrollStep, now - (lastScrollFire[axis] ?? 0) > 0.12 else { scrollAccum[axis] = acc; return true }
            scrollAccum[axis] = 0
            lastScrollFire[axis] = now
        }
        fire(b)
        return true
    }
    func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        start()
    }

    func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    func trackModifierTap(_ event: CGEvent) {
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

    static func clicks() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }

}
