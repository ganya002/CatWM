import AppKit
import CatWMKit

extension FocusDim {
    func configure(dim: Bool, strength: CGFloat, blur: Bool, radius: Int) {
        self.strength = strength
        self.radius = radius
        set(dim: dim != configured?.dim ? dim : dims, blur: blur != configured?.blur ? blur : blurs)
        configured = (dim, blur)
    }

    func toggleDim() {
        set(dim: !dims, blur: blurs)
        WindowManager.shared.surface.showHUD(dims ? "Dimming other windows" : "Dim off", on: NSScreen.main)
    }

    func toggleBlur() {
        set(dim: dims, blur: !blurs)
        WindowManager.shared.surface.showHUD(blurs ? "Blurring other windows" : "Blur off", on: NSScreen.main)
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
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            notificationObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.update()
            })
        }
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuild()
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.update()
        })
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.update() }
    }

    func apply() {
        guard enabled else { return }
        guard let (id, layer) = focusedWindow() else { return hideAll() }
        layoutPanels()
        let level = NSWindow.Level(rawValue: layer)
        if id == target {
            for pair in pairs.values { pair.front.level = level; pair.front.order(.below, relativeTo: Int(id)) }
            return
        }
        let first = target == nil
        target = id
        generation += 1
        let gen = generation
        for (display, var pair) in pairs {
            swap(&pair.front, &pair.spare)
            pairs[display] = pair
            let incoming = pair.front, outgoing = pair.spare
            incoming.level = level
            if first || !incoming.isVisible { incoming.alphaValue = 0 }
            incoming.order(.below, relativeTo: Int(id))
            Motion.group(fade, curve: Motion.Curve.fade, changes: {
                Motion.setAlpha(1, on: incoming)
                if outgoing.isVisible { Motion.setAlpha(0, on: outgoing) }
            }, completion: { [weak self] in
                guard self?.generation == gen else { return }
                outgoing.orderOut(nil)
            })
        }
    }

    func hideAll() {
        target = nil
        generation += 1
        let gen = generation
        let panels = pairs.values.flatMap { [$0.front, $0.spare] }.filter(\.isVisible)
        guard !panels.isEmpty else { return }
        Motion.group(fade, curve: Motion.Curve.fade, changes: {
            panels.forEach { Motion.setAlpha(0, on: $0) }
        }, completion: { [weak self] in
            guard self?.generation == gen else { return }
            panels.forEach { $0.orderOut(nil) }
        })
    }

    func focusedWindow() -> (CGWindowID, Int)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var id: CGWindowID?
        if app.processIdentifier == getpid() {
            if let number = NSApp.keyWindow?.windowNumber, number > 0, !owns(number) { id = CGWindowID(number) }
        } else if let report = WindowManager.shared.focusRequests.reportedFocus, report.pid == app.processIdentifier {
            id = report.id
        }
        if id == nil { id = CGWindowInfo.onScreen().first { $0.pid == app.processIdentifier }?.id }
        guard let id, let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let rawBounds = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary),
              bounds.width >= 60, bounds.height >= 40,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return nil }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        guard (0..<Int(CGWindowLevelForKey(.mainMenuWindow))).contains(layer) else { return nil }
        guard NSScreen.screens.contains(where: { flipped($0.frame).intersects(bounds) }) else { return nil }
        return (id, layer)
    }

    func flipped(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}
