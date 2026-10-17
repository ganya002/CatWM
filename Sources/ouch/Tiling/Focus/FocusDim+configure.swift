import AppKit

extension FocusDim {
    func configure(dim: Bool, strength: CGFloat, blur: Bool, radius: Int) {
        self.strength = strength
        self.radius = radius
        set(dim: dim != configured?.dim ? dim : dims, blur: blur != configured?.blur ? blur : blurs)
        configured = (dim, blur)
    }

    func toggleDim() {
        set(dim: !dims, blur: blurs)
        HUD.shared.show(dims ? "Dimming other windows" : "Dim off", on: NSScreen.main)
    }

    func toggleBlur() {
        set(dim: dims, blur: !blurs)
        HUD.shared.show(blurs ? "Blurring other windows" : "Blur off", on: NSScreen.main)
    }

    func set(dim: Bool, blur: Bool) {
        let was = enabled
        dims = dim
        blurs = blur
        pairs.values.forEach { style($0.front); style($0.spare) }
        if enabled && !was {
            observe()
            update()
        } else if !enabled && was {
            hideAll()
        }
    }

    func update() {
        guard enabled, !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            self?.pending = false
            self?.apply()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in self?.apply() }
    }

    func owns(_ windowNumber: Int) -> Bool { panelNumbers.contains(windowNumber) }

    func observe() {
        guard !observing else { return }
        observing = true
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.update() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.update() }
    }

    func apply() {
        guard enabled else { return }
        guard let (id, layer) = focusedWindow() else { return hideAll() }
        layoutPanels()
        let level = NSWindow.Level(rawValue: layer)
        if id == target {
            for p in pairs.values { p.front.level = level; p.front.order(.below, relativeTo: Int(id)) }
            return
        }
        let first = target == nil
        target = id
        generation += 1
        let gen = generation
        for (display, var p) in pairs {
            swap(&p.front, &p.spare)
            pairs[display] = p
            let incoming = p.front, outgoing = p.spare
            incoming.level = level
            if first || !incoming.isVisible { incoming.alphaValue = 0 }
            incoming.order(.below, relativeTo: Int(id))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = fade
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                incoming.animator().alphaValue = 1
                if outgoing.isVisible { outgoing.animator().alphaValue = 0 }
            } completionHandler: { [weak self] in
                guard self?.generation == gen else { return }
                outgoing.orderOut(nil)
            }
        }
    }

    func hideAll() {
        target = nil
        generation += 1
        let gen = generation
        let panels = pairs.values.flatMap { [$0.front, $0.spare] }.filter(\.isVisible)
        guard !panels.isEmpty else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = fade
            panels.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            guard self?.generation == gen else { return }
            panels.forEach { $0.orderOut(nil) }
        }
    }

    func focusedWindow() -> (CGWindowID, Int)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var id: CGWindowID?
        if app.processIdentifier == getpid() {
            if let n = NSApp.keyWindow?.windowNumber, n > 0, !owns(n) { id = CGWindowID(n) }
        } else if var el = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute) {
            if el.string(kAXRoleAttribute) == kAXSheetRole, let parent = el.element(kAXParentAttribute) { el = parent }
            id = el.windowID
        }
        if id == nil { id = CGWindowInfo.onScreen().first { $0.pid == app.processIdentifier }?.id }
        guard let id, let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let b = info[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: b),
              bounds.width >= 60, bounds.height >= 40,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return nil }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        guard (0..<Int(CGWindowLevelForKey(.mainMenuWindow))).contains(layer) else { return nil }
        guard NSScreen.screens.contains(where: { flipped($0.frame).intersects(bounds) }) else { return nil }
        return (id, layer)
    }

    func flipped(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

}
