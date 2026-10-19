import AppKit

extension WindowManager {
    @discardableResult
    func goToSpace(_ number: Int, autoCorrect: Bool = true) -> Int? {
        if let combo = SystemShortcut.desktop(number) {
            Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags)
            pendingSpace = nil
            return 1
        }
        let screens = Screen.all()
        let point = mouseLocation()
        guard let screen = screens.first(where: { $0.frame.contains(point) }) ?? currentScreen(),
              let info = Spaces.list(display: screen.uuid), var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard number >= 1, number <= info.desktops.count else {
            HUD.shared.show("There is no space \(number)", on: screen.nsScreen)
            return nil
        }
        if let pending = pendingSpace, pending.display == screen.uuid, Date() < pending.until { cur = pending.index }
        let delta = info.desktops[number - 1] - cur
        guard delta != 0 else { return 0 }
        guard let combo = SystemShortcut.step(right: delta > 0) else {
            HUD.shared.show("Turn on “Move left/right a space” in Keyboard Shortcuts", on: screen.nsScreen)
            return nil
        }
        Log.info(
            "spaces: desktop \(cur + 1) → \(number), stepping \(delta) with key \(combo.keyCode) "
                + "flags \(combo.flags.rawValue) style \(Hotkeys.postStyle)"
        )
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = PendingSpace(display: screen.uuid, index: info.desktops[number - 1],
                                    until: Date().addingTimeInterval(settle))
        spaceGeneration += 1
        let generation = spaceGeneration
        guard autoCorrect else { return abs(delta) }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: screen.uuid, target: info.desktops[number - 1], generation: generation,
                               attemptsLeft: 2)
        }
        return abs(delta)
    }

    func switchSpace(_ number: Int) { goToSpace(number) }

    func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
        guard generation == spaceGeneration, attemptsLeft > 0,
              let info = Spaces.list(display: display), let cur = info.current, cur != target,
              let combo = SystemShortcut.step(right: target > cur) else { return }
        let delta = target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        pendingSpace = PendingSpace(display: display, index: target, until: Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: display, target: target, generation: generation, attemptsLeft: attemptsLeft - 1)
        }
    }

    func moveToSpace(_ number: Int) {
        guard !movingToSpace, let window = focusedWindow() else { return }
        let frame = window.frame
        guard !frame.isNull else { return }
        let points = grabPoints(for: window, frame: frame)
        guard !points.isEmpty else {
            HUD.shared.show("This window has nothing to grab", on: screen(of: window)?.nsScreen)
            Log.info("move to space: no grab point for \(window.bundleID ?? "pid \(window.pid)")")
            return
        }
        movingToSpace = true
        focus(window, warp: false)
        tryGrab(window, points[...], space: number, restore: mouseLocation())
    }

    func postMouse(_ type: CGEventType, _ point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    func attemptGrab(_ window: Window, at point: CGPoint, completion: @escaping (Bool, CGPoint) -> Void) {
        let before = serverFrame(window.id) ?? window.frame
        let offsets: [CGFloat] = [4, 12, 22]
        let lastOffset = offsets.last ?? 0
        postMouse(.leftMouseDown, point)
        func step(_ index: Int) {
            guard index < offsets.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                    guard let self else { return }
                    let after = serverFrame(window.id) ?? window.frame
                    let grabbed = !after.approxEqual(before, tolerance: 4)
                    Log.info(
                        "move to space: pressed \(window.bundleID ?? "pid \(window.pid)") at \(point); "
                            + "frame \(before) → \(after)"
                    )
                    completion(grabbed, CGPoint(x: point.x + lastOffset, y: point.y))
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 0.05 : 0.025)) { [weak self] in
                self?.postMouse(.leftMouseDragged, CGPoint(x: point.x + offsets[index], y: point.y))
                step(index + 1)
            }
        }
        step(0)
    }

    func tryGrab(_ window: Window, _ points: ArraySlice<CGPoint>, space number: Int, restore: CGPoint) {
        guard let point = points.first else {
            Log.info("move to space: couldn't grab \(window.bundleID ?? "pid \(window.pid)")")
            HUD.shared.show("Couldn't grab this window", on: screen(of: window)?.nsScreen)
            finishMove(restore: restore)
            return
        }
        let original = serverFrame(window.id) ?? window.frame
        attemptGrab(window, at: point) { [weak self] grabbed, held in
            guard let self else { return }
            guard grabbed else {
                postMouse(.leftMouseUp, held)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
                    self?.tryGrab(window, points.dropFirst(), space: number, restore: restore)
                }
                return
            }
            Log.info("move to space: holding \(window.bundleID ?? "pid \(window.pid)"), going to space \(number)")
            rememberGrab(window, point, frame: original)
            guard let steps = goToSpace(number, autoCorrect: false), steps > 0 else {
                postMouse(.leftMouseUp, held)
                finishMove(restore: restore)
                return
            }
            holdUntilArrived(space: number, release: held, restore: restore,
                             settle: 0.45 + 0.15 * Double(steps - 1), attemptsLeft: 2)
        }
    }
}
