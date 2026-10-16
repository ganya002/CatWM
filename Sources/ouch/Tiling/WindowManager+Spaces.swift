// Tiling: macOS Spaces: switches desktops and moves windows between Spaces by grabbing them.
import AppKit

extension WindowManager {
    // MARK: - Spaces

    /// Goes to desktop `n` (1-based) on the display under the pointer. Uses "Switch to Desktop N" when
    /// it's turned on in Keyboard Shortcuts; otherwise steps there with "Move left/right a space",
    /// which macOS has on by default. Returns how many switches were posted, or nil on failure.
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
        // macOS sometimes drops a step when presses reverse direction mid-slide. Once it settles,
        // check where we actually are and step the rest of the way (twice at most).
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            self?.correctSpace(display: s.uuid, target: info.desktops[n - 1], generation: generation, attemptsLeft: 2)
        }
        return abs(delta)
    }

    func switchSpace(_ n: Int) { goToSpace(n) }

    private func correctSpace(display: String, target: Int, generation: Int, attemptsLeft: Int) {
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

    // MARK: Moving windows between spaces

    /// Fallback for macOS Spaces mode: hold the window by an empty part of its title bar and switch
    /// spaces. The grab point is found by asking Accessibility what's under each candidate point,
    /// then confirmed by nudging the window and checking it followed.
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
        focus(w, warp: false) // the grab presses at its own points
        tryGrab(w, points[...], space: n, restore: mouseLocation())
    }

    private func postMouse(_ type: CGEventType, _ p: CGPoint) {
        guard let e = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type,
                              mouseCursorPosition: p, mouseButton: .left) else { return }
        e.setIntegerValueField(.eventSourceUserData, value: Hotkeys.syntheticMarker)
        e.post(tap: .cghidEventTap)
    }

    /// Presses at `p` and drags gradually. Chromium-based apps only start a window drag after the
    /// pointer passes a threshold, so a tiny nudge isn't enough. Calls back with whether the window
    /// followed, and the point where the button is still held.
    private func attemptGrab(_ w: Window, at p: CGPoint, completion: @escaping (Bool, CGPoint) -> Void) {
        let before = serverFrame(w.id) ?? w.frame
        let offsets: [CGFloat] = [4, 12, 22]
        postMouse(.leftMouseDown, p)
        func step(_ k: Int) {
            guard k < offsets.count else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
                    guard let self else { return }
                    let after = serverFrame(w.id) ?? w.frame
                    // Any frame change counts: dragging a window that fills the screen makes macOS
                    // restore its earlier size around the pointer, which can move it left.
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

    private func tryGrab(_ w: Window, _ points: ArraySlice<CGPoint>, space n: Int, restore: CGPoint) {
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
                // Not a draggable spot: let go and try the next one.
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

    /// Diagnostics (`ouch grabtest`): try each grab point on the focused window without
    /// switching spaces, logging which ones pick the window up.
    func grabTest() {
        guard !movingToSpace, let w = focusedWindow() else { Log.info("grabtest: no focused window"); return }
        let points = grabPoints(for: w, frame: w.frame)
        Log.info("grabtest: \(w.bundleID ?? "pid \(w.pid)") frame \(w.frame) candidates \(points)")
        movingToSpace = true
        let restore = mouseLocation()
        func next(_ rest: ArraySlice<CGPoint>) {
            guard let p = rest.first else { finishMove(restore: restore); return }
            let original = serverFrame(w.id) ?? w.frame
            attemptGrab(w, at: p) { [weak self] grabbed, held in
                self?.postMouse(.leftMouseUp, held)
                Log.info("grabtest: \(p) \(grabbed ? "GRABS" : "no")")
                if grabbed { self?.rememberGrab(w, p, frame: original) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { next(rest.dropFirst()) }
            }
        }
        next(points[...])
    }

    /// Keep holding the window until the switch has finished on the right space, correcting any
    /// step macOS dropped, then let go.
    private func holdUntilArrived(space n: Int, release: CGPoint, restore: CGPoint, waited: Double, settle: Double, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
            guard let self else { return }
            let p = mouseLocation()
            if attemptsLeft > 0, let s = Screen.all().first(where: { $0.frame.contains(p) }),
               let info = Spaces.list(display: s.uuid), let cur = info.current, info.desktops.indices.contains(n - 1),
               cur != info.desktops[n - 1], let combo = SystemShortcut.step(right: info.desktops[n - 1] > cur) {
                let delta = info.desktops[n - 1] - cur
                Log.info("move to space: landed on \(cur + 1); stepping \(delta) more")
                for _ in 0..<abs(delta) { Hotkeys.post(keyCode: combo.keyCode, flags: combo.flags) }
                holdUntilArrived(space: n, release: release, restore: restore, waited: waited + settle,
                                 settle: 0.45 + 0.15 * Double(abs(delta) - 1), attemptsLeft: attemptsLeft - 1)
                return
            }
            postMouse(.leftMouseUp, release)
            finishMove(restore: restore)
        }
    }

    private func finishMove(restore: CGPoint) {
        CGWarpMouseCursorPosition(restore)
        CursorRefresh.soon()
        drags = [:]
        movingToSpace = false
        scheduleRefresh(after: 0.2)
    }

    /// The window server's idea of the frame; it updates during a title-bar drag before AX does.
    private func serverFrame(_ id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let b = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b)
    }

    private func rememberGrab(_ w: Window, _ p: CGPoint, frame f: CGRect) {
        guard let id = w.bundleID else { return }
        let hint = (CGPoint(x: p.x - f.minX, y: p.y - f.minY), CGPoint(x: f.maxX - p.x, y: p.y - f.minY))
        grabHints[id] = hint
        UserDefaults.standard.set(grabHints.mapValues { [Double($0.fromLeft.x), Double($0.fromLeft.y), Double($0.fromRight.x), Double($0.fromRight.y)] },
                                  forKey: "grabHints")
    }

    /// Candidate spots to hold a window by, best first: where it worked last time for this app,
    /// spots on the bare window background, then everything else along the top strip that isn't a
    /// control. Each one is still confirmed by a test drag.
    private func grabPoints(for w: Window, frame f: CGRect) -> [CGPoint] {
        var raw: [CGPoint] = []
        if let id = w.bundleID, let h = grabHints[id] {
            raw.append(CGPoint(x: f.minX + h.fromLeft.x, y: f.minY + h.fromLeft.y))
            raw.append(CGPoint(x: f.maxX - h.fromRight.x, y: f.minY + h.fromRight.y))
        }
        if let zoom = w.element.element(kAXZoomButtonAttribute)?.frame, !zoom.isNull {
            raw.append(CGPoint(x: zoom.maxX + 14, y: zoom.midY))
        }
        // Not the top few pixels: that's the resize border in apps that draw their own title bar.
        for dy: CGFloat in [9, 15, 22, 30] {
            var x = f.minX + 72
            while x < f.maxX - 30 {
                raw.append(CGPoint(x: x, y: f.minY + dy))
                x += 22
            }
        }
        let app = axApp(w.pid)
        let blocked: Set<String> = [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXTextFieldRole, kAXTextAreaRole,
                                    kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole, kAXSliderRole, "AXLink",
                                    kAXIncrementorRole, "AXTab", kAXImageRole, kAXScrollAreaRole, "AXWebArea",
                                    kAXStaticTextRole, kAXMenuBarRole, kAXMenuItemRole]
        let background: Set<String> = [kAXWindowRole, kAXGroupRole, kAXToolbarRole, kAXUnknownRole, kAXSplitGroupRole, "AXTabGroup"]
        var best: [CGPoint] = [], ok: [CGPoint] = [], unknown: [CGPoint] = []
        var skipped: [String: Int] = [:]
        let hinted = grabHints[w.bundleID ?? ""] != nil ? 2 : 0
        var hintedCount = 0
        for (k, p) in raw.enumerated() where f.contains(p) {
            if k < hinted { best.append(p); hintedCount += 1; continue }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &hit) == .success, let hit else {
                unknown.append(p); continue
            }
            let role = hit.string(kAXRoleAttribute) ?? "?"
            if blocked.contains(role) { skipped[role, default: 0] += 1; continue }
            var actions: CFArray?
            if AXUIElementCopyActionNames(hit, &actions) == .success,
               let names = actions as? [String], names.contains(kAXPressAction) { skipped["\(role)+press", default: 0] += 1; continue }
            let owner = role == kAXWindowRole ? hit : hit.element(kAXWindowAttribute)
            if let owner, let oid = owner.windowID, oid != w.id { skipped["covered", default: 0] += 1; continue }
            if background.contains(role) { best.append(p) } else { ok.append(p) }
        }
        // Spread the picks out (neighbouring points usually hit the same element) and alternate
        // between the left and right ends, where the empty gaps in toolbars usually are.
        func spaced(_ ps: [CGPoint], _ limit: Int) -> [CGPoint] {
            var thin: [CGPoint] = []
            for p in ps where !thin.contains(where: { abs($0.x - p.x) < 30 && abs($0.y - p.y) < 6 }) { thin.append(p) }
            let sorted = thin.sorted { $0.x < $1.x }
            var out: [CGPoint] = []
            var lo = 0, hi = sorted.count - 1
            while lo <= hi && out.count < limit {
                out.append(sorted[lo]); lo += 1
                if lo <= hi && out.count < limit { out.append(sorted[hi]); hi -= 1 }
            }
            return out
        }
        let hintedPicks = Array(best[..<hintedCount])
        let rest = Array(best.dropFirst(hintedCount))
        let picks = Array((hintedPicks + spaced(rest, 14) + spaced(ok, 4) + spaced(unknown, 2)).prefix(20))
        Log.info("move to space: \(picks.count) grab candidates for \(w.bundleID ?? "pid \(w.pid)"); skipped \(skipped)")
        return picks
    }
}
