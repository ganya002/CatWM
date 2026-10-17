import AppKit

extension WindowManager {
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

    func holdUntilArrived(space n: Int, release: CGPoint, restore: CGPoint, waited: Double, settle: Double, attemptsLeft: Int) {
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

    func finishMove(restore: CGPoint) {
        CGWarpMouseCursorPosition(restore)
        CursorRefresh.soon()
        drags = [:]
        movingToSpace = false
        scheduleRefresh(after: 0.2)
    }

    func serverFrame(_ id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let b = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: b)
    }

    func rememberGrab(_ w: Window, _ p: CGPoint, frame f: CGRect) {
        guard let id = w.bundleID else { return }
        let hint = (CGPoint(x: p.x - f.minX, y: p.y - f.minY), CGPoint(x: f.maxX - p.x, y: p.y - f.minY))
        grabHints[id] = hint
        UserDefaults.standard.set(grabHints.mapValues { [Double($0.fromLeft.x), Double($0.fromLeft.y), Double($0.fromRight.x), Double($0.fromRight.y)] },
                                  forKey: "grabHints")
    }

    func grabPoints(for w: Window, frame f: CGRect) -> [CGPoint] {
        var raw: [CGPoint] = []
        if let id = w.bundleID, let h = grabHints[id] {
            raw.append(CGPoint(x: f.minX + h.fromLeft.x, y: f.minY + h.fromLeft.y))
            raw.append(CGPoint(x: f.maxX - h.fromRight.x, y: f.minY + h.fromRight.y))
        }
        if let zoom = w.element.element(kAXZoomButtonAttribute)?.frame, !zoom.isNull {
            raw.append(CGPoint(x: zoom.maxX + 14, y: zoom.midY))
        }
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
