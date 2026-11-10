import AppKit

extension WindowManager {
    @discardableResult
    package func goToSpace(_ number: Int, autoCorrect: Bool = true) -> Int? {
        if let combo = SystemShortcut.desktop(number) {
            Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags, style: keyPostStyle)
            desktops.pendingSpace = nil
            return 1
        }
        let screens = backend.screens()
        let point = mouseLocation()
        guard let screen = screens.first(where: { $0.frame.contains(point) }) ?? currentScreen(),
              let info = Spaces.list(display: screen.uuid), var cur = info.current else {
            Log.info("spaces: can't read the space list")
            return nil
        }
        guard number >= 1, number <= info.desktops.count else {
            surface.showHUD("There is no space \(number)", on: screen.nsScreen)
            return nil
        }
        if let pending = desktops.pendingSpace, pending.display == screen.uuid, Date() < pending.until {
            cur = pending.index
        }
        let delta = info.desktops[number - 1] - cur
        guard delta != 0 else { return 0 }
        guard let combo = SystemShortcut.step(right: delta > 0) else {
            surface.showHUD("Turn on “Move left/right a space” in Keyboard Shortcuts", on: screen.nsScreen)
            return nil
        }
        Log.info(
            "spaces: desktop \(cur + 1) → \(number), stepping \(delta) with key \(combo.keyCode) "
                + "flags \(combo.flags.rawValue) style \(keyPostStyle)"
        )
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags, style: keyPostStyle) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        desktops.pendingSpace = .init(display: screen.uuid, index: info.desktops[number - 1],
                                      until: Date().addingTimeInterval(settle))
        desktops.spaceGeneration += 1
        let generation = desktops.spaceGeneration
        guard autoCorrect else { return abs(delta) }
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in
            self?.correctSpace(display: screen.uuid, target: info.desktops[number - 1], generation: generation,
                               attemptsLeft: 2)
        }
        return abs(delta)
    }

    package func switchSpace(_ number: Int) { goToSpace(number) }

    package func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
        guard generation == desktops.spaceGeneration, attemptsLeft > 0,
              let info = Spaces.list(display: display), let cur = info.current, cur != target,
              let combo = SystemShortcut.step(right: target > cur) else { return }
        let delta = target - cur
        Log.info("spaces: landed on \(cur + 1) instead of \(target + 1); correcting by \(delta)")
        for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags, style: keyPostStyle) }
        let settle = 0.6 + 0.15 * Double(abs(delta))
        desktops.pendingSpace = .init(display: display, index: target, until: Date().addingTimeInterval(settle))
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in
            self?.correctSpace(display: display, target: target, generation: generation, attemptsLeft: attemptsLeft - 1)
        }
    }

    package func moveToSpace(_ number: Int) {
        guard !desktops.movingToSpace, let window = focusedWindow() else { return }
        let frame = window.frameUnlessStalled
        guard !frame.isNull else { return }
        let points = grabPoints(for: window, frame: frame)
        guard !points.isEmpty else {
            surface.showHUD("This window has nothing to grab", on: screen(of: window)?.nsScreen)
            Log.info("move to space: no grab point for \(window.bundleID ?? "pid \(window.pid)")")
            return
        }
        desktops.movingToSpace = true
        focus(window, warp: false)
        tryGrab(window, points[...], space: number, restore: mouseLocation())
    }

    package func postMouse(_ type: CGEventType, _ point: CGPoint) {
        guard input.pointerAndFocus,
              let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        event.post(tap: .cghidEventTap)
    }

    package func attemptGrab(_ window: Window, at point: CGPoint, completion: @escaping (Bool, CGPoint) -> Void) {
        let before = serverFrame(window.id) ?? window.frame
        let offsets: [CGFloat] = [4, 12, 22]
        let lastOffset = offsets.last ?? 0
        postMouse(.leftMouseDown, point)
        func step(_ index: Int) {
            guard index < offsets.count else {
                DispatchQueue.main.asyncAfter( // style-ok: a grabbed window moves with no event
                    deadline: .now() + 0.09
                ) { [weak self] in
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
            DispatchQueue.main.asyncAfter( // style-ok: paces synthetic drag input
                deadline: .now() + (index == 0 ? 0.05 : 0.025)
            ) { [weak self] in
                self?.postMouse(.leftMouseDragged, CGPoint(x: point.x + offsets[index], y: point.y))
                step(index + 1)
            }
        }
        step(0)
    }

    package func tryGrab(_ window: Window, _ points: ArraySlice<CGPoint>, space number: Int, restore: CGPoint) {
        guard let point = points.first else {
            Log.info("move to space: couldn't grab \(window.bundleID ?? "pid \(window.pid)")")
            surface.showHUD("Couldn't grab this window", on: screen(of: window)?.nsScreen)
            finishMove(restore: restore)
            return
        }
        let original = serverFrame(window.id) ?? window.frame
        attemptGrab(window, at: point) { [weak self] grabbed, held in
            guard let self else { return }
            guard grabbed else {
                postMouse(.leftMouseUp, held)
                DispatchQueue.main.asyncAfter( // style-ok: paces synthetic drag input
                    deadline: .now() + 0.06
                ) { [weak self] in
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
