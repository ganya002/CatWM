import AppKit

extension Hotkeys {
    package func setBindings(_ list: [KeyBinding]) {
        tables = [:]
        for bind in list { tables[bind.submap, default: [:]][Self.key(bind.keyCode, bind.mods)] = bind }
        if WindowManager.shared.input.capsLock {
            CapsLockChord.shared.setBound(list.contains { $0.keyCode == CapsLockChord.keyCode })
        }
        if !submap.isEmpty, tables[submap] == nil { setSubmap("") }
    }

    package func setSubmap(_ name: String) {
        let target = name.lowercased() == "reset" ? "" : name
        guard target != submap else { return }
        guard target.isEmpty || tables[target] != nil else {
            Log.info("submap: `\(target)` has no binds, staying out of it")
            return
        }
        submap = target
        modeChord = target.isEmpty ? []
            : CGEventSource.flagsState(.combinedSessionState).intersection(Self.tapMods).subtracting(.maskShift)
        tapDown = nil
        DispatchQueue.main.async { [weak self] in self?.onSubmapChange?(target) }
    }

    @discardableResult
    package func start() -> Bool {
        if tap != nil { return true }
        let input = WindowManager.shared.input
        guard input.keys else { return false }
        capsLock = input.capsLock
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
            | CGEventMask(1 << CGEventType.scrollWheel.rawValue) | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.rightMouseUp.rawValue)
        guard let newTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
                                             options: .defaultTap, eventsOfInterest: mask, callback: tapCallback,
                                             userInfo: nil) else { return false }
        tap = newTap
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, newTap, 0), .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        startSwipes()
        if capsLock { CapsLockChord.shared.start() }
        return true
    }

    package func stop() {
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        if let swipeMonitor { NSEvent.removeMonitor(swipeMonitor) }
        swipeMonitor = nil
        if capsLock { CapsLockChord.shared.stop() }
        setSubmap("")
    }

    package func startSwipes() {
        guard swipeMonitor == nil else { return }
        swipeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .swipe) { [weak self] event in
            guard let self, !paused else { return }
            let code: UInt16
            if event.deltaX != 0 {
                code = event.deltaX > 0 ? SpecialKey.swipeLeft : SpecialKey.swipeRight
            } else if event.deltaY != 0 {
                code = event.deltaY > 0 ? SpecialKey.swipeUp : SpecialKey.swipeDown
            } else {
                return
            }
            let flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))
            if let bind = lookup(code, flags) { fire(bind) }
        }
    }

    package func lookup(_ code: UInt16, _ flags: CGEventFlags) -> KeyBinding? {
        let key = Self.key(code, flags)
        return (submap.isEmpty ? nil : tables[submap]?[key]) ?? tables[""]?[key]
    }

    package func fireCapsLock(_ flags: CGEventFlags) -> Bool {
        guard !paused, !textInputActive, let bind = lookup(CapsLockChord.keyCode, flags),
              repeatOK(bind, nil) else { return false }
        fire(bind)
        return true
    }

    package func fire(_ bind: KeyBinding) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didFire, object: nil, userInfo: ["bind": bind])
        }
        if bind.dispatcher == "submap" {
            setSubmap(bind.arg)
        } else {
            DispatchQueue.main.async { [weak self] in self?.handler?(bind) }
        }
    }

    package func handleScroll(_ event: CGEvent) -> Bool {
        guard !paused, !textInputActive,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { return false }
        let continuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let dy = event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis1 : .scrollWheelEventDeltaAxis1)
        let dx = event.getDoubleValueField(continuous ? .scrollWheelEventPointDeltaAxis2 : .scrollWheelEventDeltaAxis2)
        let axis = abs(dy) >= abs(dx) ? 1 : 2
        let delta = axis == 1 ? dy : dx
        guard delta != 0 else { return false }
        let code = axis == 1 ? (delta > 0 ? SpecialKey.mouseUp : SpecialKey.mouseDown)
                             : (delta > 0 ? SpecialKey.mouseLeft : SpecialKey.mouseRight)
        guard let bind = lookup(code, event.flags) else { return false }
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }
        if continuous {
            if event.getIntegerValueField(.scrollWheelEventScrollPhase) == 1 { scrollAccum[axis] = 0 }
            let acc = (scrollAccum[axis] ?? 0) * (delta > 0 ? 1 : -1) >= 0 ? (scrollAccum[axis] ?? 0) + delta : delta
            let now = ProcessInfo.processInfo.systemUptime
            guard abs(acc) >= Self.scrollStep, now - (lastScrollFire[axis] ?? 0) > 0.12 else {
                scrollAccum[axis] = acc
                return true
            }
            scrollAccum[axis] = 0
            lastScrollFire[axis] = now
        }
        fire(bind)
        return true
    }
    package func restart() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            if CGEvent.tapIsEnabled(tap: tap) { return }
            CFMachPortInvalidate(tap)
            self.tap = nil
        }
        start()
    }

    package func reenable() { if let tap { CGEvent.tapEnable(tap: tap, enable: true) } }

    package func disable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        setSubmap("")
    }

    package func observe(_ type: CGEventType, _ event: CGEvent) {
        guard type == .flagsChanged else { tapDown = nil; return }
        if let onFlagsChanged {
            let flags = event.flags
            DispatchQueue.main.async { onFlagsChanged(flags) }
        }
        trackModifierTap(event)
    }

    package func trackModifierTap(_ event: CGEvent) {
        let mods = event.flags.intersection(Self.tapMods)
        defer { lastMods = mods }
        guard onModifierTap != nil, !paused, !submap.isEmpty,
              event.getIntegerValueField(.keyboardEventKeycode) != Int64(CapsLockChord.keyCode),
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else { tapDown = nil; return }
        if let down = tapDown {
            tapDown = nil
            if mods.isEmpty, ProcessInfo.processInfo.systemUptime - down.time < Self.tapLimit,
               Self.clicks() == down.clicks {
                DispatchQueue.main.async { [weak self] in self?.onModifierTap?() }
            }
            return
        }
        let allowed = WindowManager.shared.config.mainMod.union(modeChord)
        if lastMods.isEmpty, mods.rawValue.nonzeroBitCount == 1, allowed.contains(mods) {
            tapDown = TapDown(flag: mods, time: ProcessInfo.processInfo.systemUptime, clicks: Self.clicks())
        }
    }

    package static func clicks() -> UInt32 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown]
            .reduce(0) { $0 &+ CGEventSource.counterForEventType(.combinedSessionState, eventType: $1) }
    }
}
