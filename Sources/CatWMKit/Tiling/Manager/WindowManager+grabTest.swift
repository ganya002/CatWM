import AppKit

extension WindowManager {
    private struct GrabCandidates {
        package var best: [CGPoint] = []
        package var usable: [CGPoint] = []
        package var unknown: [CGPoint] = []
        package var skipped: [String: Int] = [:]
        package var hintedCount = 0
    }

    private static let blockedGrabRoles: Set<String> = [
        kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXTextFieldRole, kAXTextAreaRole,
        kAXPopUpButtonRole, kAXMenuButtonRole, kAXComboBoxRole, kAXSliderRole, "AXLink",
        kAXIncrementorRole, "AXTab", kAXImageRole, kAXScrollAreaRole, "AXWebArea",
        kAXStaticTextRole, kAXMenuBarRole, kAXMenuItemRole
    ]

    private static let backgroundGrabRoles: Set<String> = [
        kAXWindowRole, kAXGroupRole, kAXToolbarRole, kAXUnknownRole, kAXSplitGroupRole, "AXTabGroup"
    ]

    package func grabTest() {
        guard !desktops.movingToSpace, let window = focusedWindow() else {
            Log.info("grabtest: no focused window")
            return
        }
        let points = grabPoints(for: window, frame: window.frame)
        Log.info("grabtest: \(window.bundleID ?? "pid \(window.pid)") frame \(window.frame) candidates \(points)")
        desktops.movingToSpace = true
        let restore = mouseLocation()
        func next(_ rest: ArraySlice<CGPoint>) {
            guard let point = rest.first else { finishMove(restore: restore); return }
            let original = serverFrame(window.id) ?? window.frame
            attemptGrab(window, at: point) { [weak self] grabbed, held in
                self?.postMouse(.leftMouseUp, held)
                Log.info("grabtest: \(point) \(grabbed ? "GRABS" : "no")")
                if grabbed { self?.rememberGrab(window, point, frame: original) }
                DispatchQueue.main.asyncAfter( // style-ok: paces a developer test
                    deadline: .now() + 0.3
                ) { next(rest.dropFirst()) }
            }
        }
        next(points[...])
    }

    package func holdUntilArrived(space number: Int, release: CGPoint, restore: CGPoint, settle: Double,
                                  attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter( // style-ok: no event marks the last queued Desktop step
            deadline: .now() + settle
        ) { [weak self] in
            guard let self else { return }
            let point = mouseLocation()
            if attemptsLeft > 0, let screen = backend.screens().first(where: { $0.frame.contains(point) }),
               let info = backend.spaceList(display: screen.uuid), let cur = info.current,
               info.desktops.indices.contains(number - 1),
               cur != info.desktops[number - 1],
               let combo = backend.stepShortcut(right: info.desktops[number - 1] > cur) {
                let delta = info.desktops[number - 1] - cur
                Log.info("move to space: landed on \(cur + 1); stepping \(delta) more")
                for _ in 0..<abs(delta) {
                    postKey(combo)
                }
                holdUntilArrived(space: number, release: release, restore: restore,
                                 settle: 0.45 + 0.15 * Double(abs(delta) - 1), attemptsLeft: attemptsLeft - 1)
                return
            }
            postMouse(.leftMouseUp, release)
            finishMove(restore: restore)
        }
    }

    package func finishMove(restore: CGPoint) {
        warpPointer(to: restore)
        drags = [:]
        desktops.movingToSpace = false
        scheduleRefresh(after: 0.2)
    }

    package func serverFrame(_ id: CGWindowID) -> CGRect? { backend.serverFrame(of: id) }

    package func rememberGrab(_ window: Window, _ point: CGPoint, frame: CGRect) {
        guard let id = window.bundleID else { return }
        let hint = (CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                    CGPoint(x: frame.maxX - point.x, y: point.y - frame.minY))
        grabHints[id] = hint
        let saved = grabHints.mapValues {
            [Double($0.fromLeft.x), Double($0.fromLeft.y), Double($0.fromRight.x), Double($0.fromRight.y)]
        }
        Instance.defaults.set(saved, forKey: DefaultsKey.grabHints)
    }

    package func grabPoints(for window: Window, frame: CGRect) -> [CGPoint] {
        let raw = rawGrabPoints(for: window, frame: frame)
        let candidates = classifyGrabPoints(raw, for: window, frame: frame)
        let hintedPicks = Array(candidates.best[..<candidates.hintedCount])
        let rest = Array(candidates.best.dropFirst(candidates.hintedCount))
        let picks = Array((hintedPicks + Self.spaced(rest, 14) + Self.spaced(candidates.usable, 4)
                           + Self.spaced(candidates.unknown, 2)).prefix(20))
        Log.info(
            "move to space: \(picks.count) grab candidates for \(window.bundleID ?? "pid \(window.pid)"); "
                + "skipped \(candidates.skipped)"
        )
        return picks
    }

    private func rawGrabPoints(for window: Window, frame: CGRect) -> [CGPoint] {
        var raw: [CGPoint] = []
        if let id = window.bundleID, let hint = grabHints[id] {
            raw.append(CGPoint(x: frame.minX + hint.fromLeft.x, y: frame.minY + hint.fromLeft.y))
            raw.append(CGPoint(x: frame.maxX - hint.fromRight.x, y: frame.minY + hint.fromRight.y))
        }
        if let zoom = window.element.element(kAXZoomButtonAttribute)?.frame, !zoom.isNull {
            raw.append(CGPoint(x: zoom.maxX + 14, y: zoom.midY))
        }
        for dy: CGFloat in [9, 15, 22, 30] {
            var x = frame.minX + 72
            while x < frame.maxX - 30 {
                raw.append(CGPoint(x: x, y: frame.minY + dy))
                x += 22
            }
        }
        return raw
    }

    private func classifyGrabPoints(_ raw: [CGPoint], for window: Window, frame: CGRect) -> GrabCandidates {
        let app = axApp(window.pid)
        var candidates = GrabCandidates()
        let hinted = grabHints[window.bundleID ?? ""] != nil ? 2 : 0
        for (index, point) in raw.enumerated() where frame.contains(point) {
            if index < hinted {
                candidates.best.append(point)
                candidates.hintedCount += 1
                continue
            }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
                  let hit else {
                candidates.unknown.append(point)
                continue
            }
            let role = hit.string(kAXRoleAttribute) ?? "?"
            if let reason = skipReason(hit, role: role, window: window) {
                candidates.skipped[reason, default: 0] += 1
                continue
            }
            if Self.backgroundGrabRoles.contains(role) {
                candidates.best.append(point)
            } else {
                candidates.usable.append(point)
            }
        }
        return candidates
    }

    private func skipReason(_ hit: AXUIElement, role: String, window: Window) -> String? {
        if Self.blockedGrabRoles.contains(role) { return role }
        var actions: CFArray?
        if AXUIElementCopyActionNames(hit, &actions) == .success,
           let names = actions as? [String], names.contains(kAXPressAction) { return "\(role)+press" }
        let owner = role == kAXWindowRole ? hit : hit.element(kAXWindowAttribute)
        if let owner, let ownerID = owner.windowID, ownerID != window.id { return "covered" }
        return nil
    }

    private static func spaced(_ points: [CGPoint], _ limit: Int) -> [CGPoint] {
        var thin: [CGPoint] = []
        for point in points where !thin.contains(where: { abs($0.x - point.x) < 30 && abs($0.y - point.y) < 6 }) {
            thin.append(point)
        }
        let sorted = thin.sorted { $0.x < $1.x }
        var out: [CGPoint] = []
        var low = 0, high = sorted.count - 1
        while low <= high && out.count < limit {
            out.append(sorted[low])
            low += 1
            if low <= high && out.count < limit {
                out.append(sorted[high])
                high -= 1
            }
        }
        return out
    }
}
