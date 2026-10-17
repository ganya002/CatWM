import AppKit
import SwiftUI

extension PermissionGuide {
    func show(_ kind: Permission = .accessibility) {
        self.kind = kind
        model.kind = kind
        finishing = false
        pending = true
        hidden = false
        sawSettings = false
        sawAlert = false
        missingTicks = 0
        waitTicks = 0
        steadyTicks = 0
        target = nil
        userMoved = false
        if panel == nil { panel = makePanel() }
        let snap = Snapshot()
        model.granted = false
        model.alertUp = snap.alert != nil
        if isShowing { update(snap) }
        follow?.invalidate()
        follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        follow?.tolerance = 0.04
    }

    func hide() {
        hidden = true
        fadeOut()
    }

    func stop() {
        follow?.invalidate()
        follow = nil
        pending = false
        fadeOut()
    }

    func granted(_ granted: Permission = .accessibility) {
        guard pending, !finishing, granted == kind else { return }
        finishing = true
        follow?.invalidate()
        follow = nil
        model.granted = true
        layout(animated: true, afterFade: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self else { return }
            finishing = false
            guard kind.isGranted else {
                model.granted = false
                layout(animated: true)
                follow = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
                follow?.tolerance = 0.04
                return
            }
            stop()
            Permission.dismissSystemAlert()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Permission.closeSettingsWindows() }
            onGranted?()
        }
    }

    func tick() {
        if kind.isGranted { granted(kind); return }
        let snap = Snapshot()
        if snap.alert != nil { sawAlert = true }
        if snap.settings != nil && snap.alert == nil { sawSettings = true }
        if snap.alert != nil || snap.settings != nil {
            missingTicks = 0
        } else if sawSettings || sawAlert {
            missingTicks += 1
            if missingTicks >= (sawSettings ? 5 : 10) { stop(); return }
        }
        update(snap)
    }

    func update(_ snap: Snapshot) {
        let alertUp = snap.alert != nil
        let contentChanged = model.alertUp != alertUp
        if contentChanged { model.alertUp = alertUp }
        let t = snap.alert ?? snap.settings
        if t.map({ old in target.map { $0.equalTo(old) } ?? false }) ?? (target == nil) {
            steadyTicks += 1
        } else {
            target = t
            steadyTicks = 0
        }
        guard !hidden, let panel else { return }
        if !isShowing {
            waitTicks += 1
            if (target != nil && steadyTicks >= 1) || waitTicks >= 8 { appear() }
            return
        }
        if let placed, Date().timeIntervalSince(movedAt) > 0.5,
           abs(panel.frame.minX - placed.minX) > 1 || abs(panel.frame.maxY - placed.maxY) > 1 { userMoved = true }
        if contentChanged { layout(animated: true, afterFade: true) }
        else if steadyTicks == 1 && target != nil { layout(animated: true) }
    }

    func desiredFrame() -> NSRect {
        let size = host?.fittingSize ?? panel?.frame.size ?? .zero
        if let cur = panel?.frame, isShowing, userMoved || target == nil {
            return NSRect(x: cur.minX, y: cur.maxY - size.height, width: size.width, height: size.height)
        }
        guard let t = target else {
            let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            return NSRect(x: area.maxX - size.width - 40, y: area.midY - size.height / 2, width: size.width, height: size.height)
        }
        let screen = NSScreen.screens.first { $0.frame.intersects(t) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame
        var o = NSPoint(x: t.maxX + gap, y: t.maxY - size.height)
        if o.x + size.width > area.maxX { o.x = t.minX - gap - size.width }
        if o.x < area.minX { o.x = area.maxX - size.width - gap }
        o.y = min(max(o.y, area.minY), area.maxY - size.height)
        return NSRect(origin: o, size: size).integral
    }

    func layout(animated: Bool, afterFade: Bool = false) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (afterFade ? 0.22 : 0)) { [weak self] in
            guard let self, let panel else { return }
            let frame = desiredFrame()
            placed = frame
            guard !frame.equalTo(panel.frame) else { return }
            movedAt = Date()
            if animated && panel.isVisible {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.28
                    ctx.timingFunction = Motion.Curve.settle
                    panel.animator().setFrame(frame, display: true)
                }
            } else {
                panel.setFrame(frame, display: true)
            }
        }
    }

}
