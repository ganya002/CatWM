import AppKit

extension WindowManager {
    @discardableResult
    func goToSpace(_ n: Int, autoCorrect: Bool = true) -> Int? {
        if let combo = SystemShortcut.desktop(n) {
            Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags)
            pendingSpace = nil
            return 1
        }
        let screens = Screen.all()
        let p = mouseLocation()
        guard let s = screens.first(where: { $0.frame.contains(p) }) ?? currentScreen(),
              let info = Spaces.list(display: s.uuid), var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard n >= 1, n <= info.desktops.count else {
            HUD.shared.show("There is no space \(n)", on: s.ns)
            return nil
        }
        if let p = pendingSpace, p.display == s.uuid, Date() < p.until { cur = p.index }
        let delta = info.desktops[n - 1] - cur
        guard delta != 0 else { return 0 }
        guard let combo = SystemShortcut.step(right: delta > 0) else {
            HUD.shared.show("Turn on “Move left/right a space” in Keyboard Shortcuts", on: s.ns)
            return nil
        }
        Log.info("spaces: desktop \(cur + 1) → \(n), stepping \(delta) with key \(combo.keyCode) flags \(combo.flags.rawValue) style \(Hotkeys.postStyle)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = (s.uuid, info.desktops[n - 1], Date().addingTimeInterval(settle))
        spaceGeneration += 1
        let generation = spaceGeneration
        guard autoCorrect else { return abs(delta) }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: s.uuid, target: info.desktops[n - 1], generation: generation, attemptsLeft: 2)
        }
        return abs(delta)
    }

    func switchSpace(_ n: Int) { goToSpace(n) }

    func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
        guard generation == spaceGeneration, attemptsLeft > 0,
              let info = Spaces.list(display: display), let cur = info.current, cur != target,
              let combo = SystemShortcut.step(right: target > cur) else { return }
        let delta = target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = (display, target, Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: display, target: target, generation: generation, attemptsLeft: attemptsLeft - 1)
        }
    }

    func moveToSpace(_ n: Int) {
        guard !movingToSpace, let w = focusedWindow() else { return }
        let f = w.frame
        guard !f.isNull else { return }
        let points = grabPoints(for: w, frame: f)
        guard !points.isEmpty else {
            HUD.shared.show("This window has nothing to grab", on: screen(of: w)?.ns)
            Log.info("move to space: no grab point for \(w.bundleID ?? "pid \(w.pid)")")
            return
        }
        movingToSpace = true
        focus(w, warp: false)
        tryGrab(w, points[...], space: n, restore: mouseLocation())
    }

    func postMouse(_ type: CGEventType, _ p: CGPoint) {
        guard let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                              mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    func attemptGrab(_ w: Window, at p: CGPoint, completion: @escaping (Bool, CGPoint) -> Void) {
        let before = serverFrame(w.id) ?? w.frame
        let offsets: [CGFloat] = [4, 12, 22]
        postMouse(.leftMouseDown, p)
        func step(_ k: Int) {
            guard k < offsets.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                    guard let self else { return }
                    let after = serverFrame(w.id) ?? w.frame
                    let grabbed = !after.approxEqual(before, tolerance: 4)
                    Log.info("move to space: pressed \(w.bundleID ?? "pid \(w.pid)") at \(p); frame \(before) → \(after)")
                    completion(grabbed, CGPoint(x: p.x + offsets.last!, y: p.y))
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (k == 0 ? 0.05 : 0.025)) { [weak self] in
                self?.postMouse(.leftMouseDragged, CGPoint(x: p.x + offsets[k], y: p.y))
                step(k + 1)
            }
        }
        step(0)
    }

    func tryGrab(_ w: Window, _ points: ArraySlice<CGPoint>, space n: Int, restore: CGPoint) {
        guard let p = points.first else {
            Log.info("move to space: couldn't grab \(w.bundleID ?? "pid \(w.pid)")")
            HUD.shared.show("Couldn't grab this window", on: screen(of: w)?.ns)
            finishMove(restore: restore)
            return
        }
        let original = serverFrame(w.id) ?? w.frame
        attemptGrab(w, at: p) { [weak self] grabbed, held in
            guard let self else { return }
            guard grabbed else {
                postMouse(.leftMouseUp, held)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.tryGrab(w, points.dropFirst(), space: n, restore: restore)
                }
                return
            }
            Log.info("move to space: holding \(w.bundleID ?? "pid \(w.pid)"), going to space \(n)")
            rememberGrab(w, p, frame: original)
            guard let steps = goToSpace(n, autoCorrect: false), steps > 0 else {
                postMouse(.leftMouseUp, held)
                finishMove(restore: restore)
                return
            }
            holdUntilArrived(space: n, release: held, restore: restore, waited: 0,
                             settle: 0.45 + 0.15 * Double(steps - 1), attemptsLeft: 2)
        }
    }

}
