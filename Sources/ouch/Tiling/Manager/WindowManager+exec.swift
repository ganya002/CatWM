import AppKit

extension WindowManager {
    func exec(_ cmd: String) {
        guard !cmd.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }

    func focusMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let src = currentScreen(), let dst = screen(from: src, spec: spec, in: screens) else { return }
        let p = CGWindowInfo.onScreen().first { info in
            guard visible.contains(info.id), let w = windows[info.id] else { return false }
            return screen(of: w, in: screens)?.uuid == dst.uuid
        }
        if let id = p?.id ?? tiled(on: dst).first, let w = windows[id] {
            focus(w)
        } else {
            CGWarpMouseCursorPosition(dst.center)
            CursorRefresh.soon()
        }
    }

    func moveToMonitor(_ spec: String) {
        let screens = Screen.all()
        guard let w = focusedWindow(), let src = screen(of: w, in: screens),
              let dst = screen(from: src, spec: spec, in: screens), dst.uuid != src.uuid else { return }
        if w.isFloating {
            let f = w.frame
            var o = CGPoint(x: dst.visible.minX + (f.minX - src.visible.minX), y: dst.visible.minY + (f.minY - src.visible.minY))
            o.x = max(dst.visible.minX, min(o.x, dst.visible.maxX - f.width))
            o.y = max(dst.visible.minY, min(o.y, dst.visible.maxY - f.height))
            animator.animate([.init(window: w, to: CGRect(origin: o, size: f.size), bounds: dst.visible)],
                             duration: config.animate ? config.animationDuration : 0,
                             curve: config.animationCurve, bounce: config.animationBounce)
            model.assign(w.id, to: shown[dst.uuid])
            scheduleRefresh()
        } else {
            model.assign(w.id, to: shown[dst.uuid])
            refresh()
        }
        focus(w)
    }
}
