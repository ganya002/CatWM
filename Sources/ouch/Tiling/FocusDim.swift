import AppKit

final class FocusDim {
    static let shared = FocusDim()

    private(set) var dims = false
    private(set) var blurs = false
    private var strength: CGFloat = 0.3
    private var radius = 20
    var enabled: Bool { dims || blurs }

    private struct Pair { var front: NSPanel; var spare: NSPanel }
    private var pairs: [CGDirectDisplayID: Pair] = [:]
    private(set) var panelNumbers = Set<Int>()
    private var target: CGWindowID?
    private var generation = 0
    private var pending = false
    private var observing = false
    private let fade = 0.2
    private var configured: (dim: Bool, blur: Bool)?

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

    private func set(dim: Bool, blur: Bool) {
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


    private func observe() {
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

    private func apply() {
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

    private func hideAll() {
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

    private func focusedWindow() -> (CGWindowID, Int)? {
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

    private func flipped(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }


    private func rebuild() {
        for p in pairs.values { p.front.orderOut(nil); p.spare.orderOut(nil) }
        pairs = [:]
        panelNumbers = []
        target = nil
        update()
    }

    private func layoutPanels() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let display = CGDirectDisplayID(n.uint32Value)
            seen.insert(display)
            if pairs[display] == nil { pairs[display] = Pair(front: makePanel(screen), spare: makePanel(screen)) }
            for p in [pairs[display]!.front, pairs[display]!.spare] where p.frame != screen.frame {
                p.setFrame(screen.frame, display: false)
            }
        }
        for (display, p) in pairs where !seen.contains(display) {
            p.front.orderOut(nil); p.spare.orderOut(nil)
            panelNumbers.remove(p.front.windowNumber); panelNumbers.remove(p.spare.windowNumber)
            pairs[display] = nil
        }
    }

    private func makePanel(_ screen: NSScreen) -> NSPanel {
        let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.animationBehavior = .none
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.alphaValue = 0
        panelNumbers.insert(p.windowNumber)
        style(p)
        return p
    }

    private func style(_ p: NSPanel) {
        let amount = dims ? strength : 0, blur = blurs ? radius : 0
        p.backgroundColor = NSColor.black.withAlphaComponent(max(amount, 0.01))
        if Blur.set(p.windowNumber, radius: blur) || blur == 0 {
            p.contentView = NSView()
        } else {
            let v = NSVisualEffectView()
            v.material = .fullScreenUI
            v.blendingMode = .behindWindow
            v.state = .active
            p.backgroundColor = .clear
            let tint = NSView()
            tint.wantsLayer = true
            tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(amount).cgColor
            tint.autoresizingMask = [.width, .height]
            v.addSubview(tint)
            p.contentView = v
            tint.frame = v.bounds
        }
    }

    private enum Blur {
        private typealias ConnFn = @convention(c) () -> Int32
        private typealias RadiusFn = @convention(c) (Int32, UInt32, UInt32) -> Int32
        private static let skylight = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        private static let conn: ConnFn? = symbol("SLSMainConnectionID", in: skylight)
        private static let radius: RadiusFn? = symbol("SLSSetWindowBackgroundBlurRadius", in: skylight)

        static func set(_ window: Int, radius r: Int) -> Bool {
            guard let conn, let radius, window > 0 else { return false }
            return radius(conn(), UInt32(window), UInt32(max(0, r))) == 0
        }
    }
}
