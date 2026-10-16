// Tiling: dims or blurs everything except the focused window.
import AppKit

/// Dims and/or blurs everything but the focused window, so it's the one thing that stands out.
/// One click-through panel per display, ordered directly below the focused window: that window (and
/// anything above it, like menus, the Dock and popovers) stays crisp, and every window behind it is
/// darkened and blurred by the window server. Nothing follows the window around, so tiling animations,
/// drags and resizes need no tracking. When focus moves, a second panel crossfades in under the new window.
///
/// The two effects are separate options: `dim-other-windows` with `dim-strength` (0-1), and
/// `blur-other-windows` with `blur-radius` (points). Hyprland's `dim_inactive` and `dim_strength` work
/// too. `toggledim` and `toggleblur` flip them.
final class FocusDim {
    static let shared = FocusDim()

    private(set) var dims = false
    private(set) var blurs = false
    private var strength: CGFloat = 0.3
    private var radius = 20
    var enabled: Bool { dims || blurs }

    /// Two panels per display: the one showing, and one to crossfade in when focus moves.
    private struct Pair { var front: NSPanel; var spare: NSPanel }
    private var pairs: [CGDirectDisplayID: Pair] = [:]
    /// Window numbers of every panel, so window-under-the-pointer lookups can see through them.
    private(set) var panelNumbers = Set<Int>()
    private var target: CGWindowID?
    private var generation = 0
    private var pending = false
    private var observing = false
    private let fade = 0.2
    private var configured: (dim: Bool, blur: Bool)?

    /// From the config, on launch and every reload. A `toggledim` or `toggleblur` lasts until that setting
    /// itself changes.
    func configure(dim: Bool, strength: CGFloat, blur: Bool, radius: Int) {
        self.strength = strength
        self.radius = radius
        set(dim: dim != configured?.dim ? dim : dims, blur: blur != configured?.blur ? blur : blurs)
        configured = (dim, blur)
    }

    /// `toggledim`: for this session only, like `toggletiling`.
    func toggleDim() {
        set(dim: !dims, blur: blurs)
        HUD.shared.show(dims ? "Dimming other windows" : "Dim off", on: NSScreen.main)
    }

    /// `toggleblur`: for this session only.
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

    /// Something about focus or the window stack may have changed. Coalesced to one look per turn,
    /// plus a second shortly after, since macOS raises a newly activated app's windows a beat late.
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

    // MARK: - Following focus

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
        // Our own windows (Settings, the tour) take focus without another app activating.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        // A click raises a window even when focus stays in the same app.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.update() }
    }

    private func apply() {
        guard enabled else { return }
        guard let (id, layer) = focusedWindow() else { return hideAll() }
        layoutPanels()
        let level = NSWindow.Level(rawValue: layer)
        if id == target {
            // Same window; just make sure nothing slipped in between it and the panels.
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

    /// The focused window and its window-server layer, if it's one worth spotlighting: on screen,
    /// at a normal-ish level, and big enough to be a real window (not our parked focus sink).
    private func focusedWindow() -> (CGWindowID, Int)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        var id: CGWindowID?
        if app.processIdentifier == getpid() {
            if let n = NSApp.keyWindow?.windowNumber, n > 0, !owns(n) { id = CGWindowID(n) }
        } else if var el = axApp(app.processIdentifier).element(kAXFocusedWindowAttribute) {
            if el.string(kAXRoleAttribute) == kAXSheetRole, let parent = el.element(kAXParentAttribute) { el = parent }
            id = el.windowID
        }
        // AX can't always name it (a slow app, no permission yet): the app's frontmost window is.
        if id == nil { id = CGWindowInfo.onScreen().first { $0.pid == app.processIdentifier }?.id }
        guard let id, let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let b = info[kCGWindowBounds as String] as? NSDictionary, let bounds = CGRect(dictionaryRepresentation: b),
              bounds.width >= 60, bounds.height >= 40,
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01 else { return nil }
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        guard (0..<Int(CGWindowLevelForKey(.mainMenuWindow))).contains(layer) else { return nil }
        // Our parked windows sit far off screen; don't dim everything for one of those.
        guard NSScreen.screens.contains(where: { flipped($0.frame).intersects(bounds) }) else { return nil }
        return (id, layer)
    }

    private func flipped(_ r: CGRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - Panels

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
            guard let display = screen.displayID else { continue }
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
        // Hidden by Mission Control, present on every Space and beside fullscreen apps.
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.alphaValue = 0
        panelNumbers.insert(p.windowNumber)
        style(p)
        return p
    }

    private func style(_ p: NSPanel) {
        let amount = dims ? strength : 0, blur = blurs ? radius : 0
        p.backgroundColor = NSColor.black.withAlphaComponent(max(amount, 0.01)) // never fully clear, or the blur has nothing to draw on
        if Blur.set(p.windowNumber, radius: blur) || blur == 0 {
            p.contentView = NSView()
        } else {
            // No window-server blur on this macOS: the system material is the next best thing.
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

    /// The window server's own background blur, the one behind menus and the Dock, at any radius.
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
