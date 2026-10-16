import AppKit

extension WindowManager {
    func isOnHomeSpace(_ s: Screen) -> Bool {
        guard let home = homeSpace[s.uuid] else { return true }
        return Spaces.current(display: s.uuid) == home
    }


    func isParked(_ f: CGRect, _ screens: [Screen]) -> Bool {
        guard !f.isNull, f.width > 0, f.height > 0 else { return false }
        let onScreen = screens.reduce(CGFloat(0)) { sum, s in
            let i = s.frame.intersection(f)
            return sum + (i.isNull ? 0 : i.width * i.height)
        }
        return onScreen < 400
    }

    private func parkingSpot(size: CGSize, on s: Screen, _ screens: [Screen]) -> CGPoint {
        let right = CGPoint(x: s.frame.maxX - 1, y: s.frame.maxY - 1)
        let left = CGPoint(x: s.frame.minX - size.width + 1, y: s.frame.maxY - 1)
        for o in [right, left] {
            let r = CGRect(origin: o, size: size)
            if !screens.contains(where: { $0.uuid != s.uuid && $0.frame.intersects(r) }) { return o }
        }
        return right
    }

    func park(_ id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id], isVirtual(workspaceOf[id]) else { return }
        let f = w.cachedFrame
        guard !f.isNull, !isParked(f, screens) else { return }
        if let slide, slide.outgoing.contains(id) {
            let s = workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { u in screens.first { $0.uuid == u } } ?? screens[0]
            let x = slide.forward ? s.frame.minX - f.width + 1 : s.frame.maxX - 1
            let edge = CGRect(x: x, y: f.minY, width: f.width, height: f.height)
            guard !f.approxEqual(edge, tolerance: 2), !animator.isMoving(id, to: edge) else { return }
            floatFrames[id] = floatsFreely(id) ? f : nil
            animator.animate([.init(window: w, to: edge, bounds: s.visible)],
                             duration: config.animationDuration, curve: config.animationCurve, bounce: config.animationBounce)
            return
        }
        floatFrames[id] = floatsFreely(id) ? f : nil
        cornerPark(id, screens: screens)
    }

    private func cornerPark(_ id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id] else { return }
        let s = workspaceOf[id].flatMap { monitorOf[$0] }.flatMap { u in screens.first { $0.uuid == u } } ?? screens[0]
        animator.cancel(id)
        animator.quiet(id)
        EnhancedUI.suspend(w.pid)
        w.setPosition(parkingSpot(size: w.cachedFrame.size, on: s, screens))
        EnhancedUI.resume(w.pid)
    }

    func floatsFreely(_ id: CGWindowID) -> Bool {
        guard let w = windows[id] else { return false }
        if w.isFloating || !tilingEnabled { return true }
        guard let ws = workspaceOf[id] else { return false }
        return (states[ws]?.layout ?? config.layouts.first) == .floating
    }

    func unpark(floating id: CGWindowID, screens: [Screen]) {
        guard let w = windows[id] else { return }
        let f = w.cachedFrame
        guard isParked(f, screens) else { floatFrames[id] = nil; return }
        let s = screen(of: w, in: screens) ?? screens[0]
        var r = floatFrames.removeValue(forKey: id) ?? targets[id]
            ?? CGRect(x: s.visible.midX - f.width / 2, y: s.visible.midY - f.height / 2, width: f.width, height: f.height)
        r.origin.x = max(s.visible.minX, min(r.origin.x, s.visible.maxX - r.width))
        r.origin.y = max(s.visible.minY, min(r.origin.y, s.visible.maxY - r.height))
        animator.quiet(id)
        if let from = slideStart(id, to: r, on: s) {
            animator.animate([.init(window: w, to: r, bounds: s.visible, from: from)],
                             duration: config.animationDuration, curve: config.animationCurve, bounce: config.animationBounce)
            return
        }
        EnhancedUI.suspend(w.pid)
        w.setFrame(r)
        EnhancedUI.resume(w.pid)
    }

    func beginSlide(from previous: String, to ws: String, on s: Screen) {
        if let old = slide { for id in old.outgoing where !visible.contains(id) { cornerPark(id, screens: Screen.all()) } }
        slide = nil
        guard config.animate, config.animationDuration >= 0.01 else { return }
        let outgoing = visible.filter { workspaceOf[$0] == previous }
        let arriving = present.filter { workspaceOf[$0] == ws }
        guard outgoing.count + arriving.count <= Self.maxAnimatedMoves else { return }
        let until = CACurrentMediaTime() + config.animationDuration
        slide = Slide(monitor: s.uuid, to: ws, outgoing: outgoing, forward: workspaceSort(previous, ws), until: until)
        DispatchQueue.main.asyncAfter(deadline: .now() + config.animationDuration + 0.2) { [weak self] in
            guard let self, self.slide?.until == until else { return }
            let screens = Screen.all()
            for id in outgoing where !self.visible.contains(id) { self.cornerPark(id, screens: screens) }
            self.slide = nil
        }
    }

    func slideStart(_ id: CGWindowID, to target: CGRect, on s: Screen) -> CGRect? {
        guard let slide, slide.monitor == s.uuid, slide.to == workspaceOf[id], CACurrentMediaTime() < slide.until else { return nil }
        let x = slide.forward ? s.frame.maxX - 1 : s.frame.minX - target.width + 1
        return CGRect(x: x, y: target.minY, width: target.width, height: target.height)
    }

    func restoreHiddenWindows() {
        guard config.virtualWorkspaces || !shown.isEmpty else { return }
        let screens = Screen.all()
        guard !screens.isEmpty else { return }
        saveWorkspaces()
        for (id, w) in windows {
            let f = w.frame
            guard isParked(f, screens) else { continue }
            let s = screen(of: w, in: screens) ?? screens[0]
            var r = floatFrames[id] ?? targets[id]
                ?? CGRect(x: s.visible.midX - f.width / 2, y: s.visible.midY - f.height / 2, width: f.width, height: f.height)
            r.size.width = min(r.width, s.visible.width)
            r.size.height = min(r.height, s.visible.height)
            r.origin.x = max(s.visible.minX, min(r.origin.x, s.visible.maxX - r.width))
            r.origin.y = max(s.visible.minY, min(r.origin.y, s.visible.maxY - r.height))
            EnhancedUI.suspend(w.pid)
            w.setFrame(r)
            EnhancedUI.resume(w.pid)
        }
        Log.info("workspaces: put parked windows back on screen")
    }
}
