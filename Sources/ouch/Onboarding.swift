import AppKit
import SwiftUI

/// First-run onboarding: an intro played across the screen, a welcome card for permissions and the
/// choice between Vim and WASD keys, then a keyboard tour on practice windows. Everything is
/// separate borderless panels over the desktop and real windows tiled by the real window manager;
/// there is no onboarding window. The longer keyboard tutorial runs on the same coach.
final class Onboarding {
    static let shared = Onboarding()
    private static let doneKey = "didOnboard"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

    /// The menu bar item, so the tour can point at it.
    weak var statusButton: NSStatusBarButton? {
        didSet { MenuBarTip.shared.statusButton = statusButton }
    }
    private var intro: Intro?
    private var welcome: OverlayPanel?
    private let welcomeModel = WelcomeModel()
    private var poll: Timer?
    private var coach: Coach?
    private var openedLoginItems = false
    private var offering = false
    /// Set while the first-run flow runs (rather than a tour or tutorial from the menu).
    private var firstRun = false

    var isRunning: Bool { intro != nil || welcome != nil || coach != nil || offering }

    /// Fresh installs see it, and so does anyone who hasn't granted Accessibility yet. Once per Mac.
    static func shouldShow(firstRun: Bool, trusted: Bool) -> Bool {
        !isDone && (firstRun || !trusted)
    }

    func start() {
        guard !isRunning else { return }
        firstRun = true
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let card = makeWelcome(on: screen)
        // Reduce Motion: no light show, just the card.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return showWelcome() }
        let m = WelcomeView.margin
        let intro = Intro(screen: screen, landing: card.frame.insetBy(dx: m, dy: m)) { [weak self] in
            self?.intro = nil
            self?.showWelcome()
        }
        self.intro = intro
        intro.run()
    }

    // MARK: Welcome card

    private func makeWelcome(on screen: NSScreen) -> OverlayPanel {
        welcomeModel.page = .permissions
        welcomeModel.style = KeyStyle.current
        welcomeModel.allowAccessibility = { Permissions.request() }
        welcomeModel.allowInputMonitoring = { Permissions.requestInputMonitoring() }
        welcomeModel.allowLogin = { [weak self] in
            LoginItem.set(true)
            if !LoginItem.isEnabled { // needs approval in System Settings
                self?.openedLoginItems = true
                LoginItem.openSettings()
            }
        }
        // Settings and macOS's alert close after a grant; then the card should be in front again.
        PermissionGuide.shared.onGranted = { [weak self] in self?.welcome?.makeKeyAndOrderFront(nil) }
        welcomeModel.skip = { [weak self] in self?.hideWelcome { self?.finish() } }
        welcomeModel.next = { [weak self] in
            guard AXIsProcessTrusted() else { Permissions.request(); return }
            self?.welcomeModel.page = .keys
        }
        welcomeModel.start = { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else { welcomeModel.page = .permissions; return }
            // The tour reads the keys from the config, so they're switched before it starts.
            if let style = welcomeModel.style, style != KeyStyle.current,
               let config = SettingsWindow.shared.library.config(id: style.configID) {
                SettingsWindow.shared.library.select(config)
            }
            hideWelcome { self.startTour() }
        }
        refreshWelcome()
        let host = FirstClickHostingView(rootView: WelcomeView(model: welcomeModel))
        let size = host.fittingSize
        let v = screen.visibleFrame
        // Normal level: System Settings and the permission guide open on top of it.
        let p = OverlayPanel(frame: NSRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2 - 12,
                                           width: size.width, height: size.height),
                             level: .normal, clickThrough: false, keyable: true)
        p.contentView = host
        p.isMovableByWindowBackground = true
        welcome = p
        return p
    }

    private func refreshWelcome() {
        let ax = AXIsProcessTrusted(), login = LoginItem.isEnabled
        if welcomeModel.accessibility != ax { welcomeModel.accessibility = ax }
        let im = Permissions.inputMonitoringGranted
        if welcomeModel.inputMonitoring != im { welcomeModel.inputMonitoring = im }
        if welcomeModel.login != login { welcomeModel.login = login }
        // Approved in the Login Items list we opened: close it again, like the Accessibility flow does.
        if login, openedLoginItems {
            openedLoginItems = false
            if ax { Permissions.closeSettingsWindows() }
            welcome?.makeKeyAndOrderFront(nil)
        }
    }

    private func showWelcome() {
        guard let p = welcome else { return }
        let end = p.frame
        welcomeModel.landed = false
        p.alphaValue = 0
        p.setFrame(end.offsetBy(dx: 0, dy: -14), display: false)
        p.orderFrontRegardless()
        p.makeKey() // Return reaches the card's default button
        p.invalidateShadow()
        animate(0.5) {
            p.animator().alphaValue = 1
            p.animator().setFrame(end, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.welcomeModel.landed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in // after the card lands
            if self?.isRunning == true { MenuBarTip.shared.show() }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWelcome() }
    }

    private func hideWelcome(then: @escaping () -> Void) {
        poll?.invalidate()
        poll = nil
        PermissionGuide.shared.onGranted = nil
        guard let p = welcome else { return then() }
        welcome = nil
        animate(0.3, changes: { p.animator().alphaValue = 0 }) {
            p.orderOut(nil)
            then()
        }
    }

    // MARK: Lessons

    /// The keyboard tour on its own (also from the menu bar).
    func startTour() {
        let lesson = TourLesson()
        run(lesson) { [weak self] _ in
            self?.offerSort(steps: lesson.count) { self?.finish() }
        }
    }

    /// The long, pausable tutorial from the menu bar. Picks up at the chapter it was paused in.
    func startTutorial(fromStart: Bool = false) {
        if fromStart { TutorialLesson.forget() }
        run(TutorialLesson()) { how in
            switch how {
            case .paused:
                let at = TutorialLesson.paused?.name
                HUD.shared.show(at.map { "Paused at \($0)" } ?? "Tutorial paused", on: nil)
            case .finished:
                HUD.shared.show("Tutorial complete", on: nil)
            case .skipped:
                break
            }
        }
    }

    /// Waits for the window manager, which starts a moment after Accessibility is granted.
    private func run(_ lesson: Lesson, attempts: Int = 20, then: @escaping (Coach.Ending) -> Void) {
        guard coach == nil, intro == nil, welcome == nil else { return }
        guard WindowManager.shared.isStarted, Hotkeys.shared.isActive else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.run(lesson, attempts: attempts - 1, then: then) }
            } else {
                HUD.shared.show("Ouch needs Accessibility first", on: nil)
                MenuBarTip.shared.hide()
                firstRun = false
            }
            return
        }
        Tips.shared.dismissAll()
        if SortPanel.shared.isOpen { SortPanel.shared.revert() }
        let c = Coach(lesson: lesson, statusButton: statusButton) { [weak self] how in
            self?.coach = nil
            then(how)
        }
        coach = c
        c.start()
        if firstRun { MenuBarTip.shared.show() }
    }

    /// When the tour hands the user's windows back crowded onto one workspace, offers to sort them.
    private func offerSort(steps: Int, then: @escaping () -> Void) {
        let wm = WindowManager.shared
        guard wm.config.sortNudge > 0, let hit = wm.shownWorkspaces().first, hit.count > wm.config.sortNudge else { return then() }
        offering = true
        MenuBarTip.shared.suppressed = true
        SortNudge.shared.markOffered(hit.workspace)
        SortOffer.shared.show(steps: steps, workspace: hit.workspace, count: hit.count, button: statusButton, on: hit.screen) { [weak self] sort in
            self?.offering = false
            MenuBarTip.shared.suppressed = false
            then()
            if sort { SortPanel.shared.open() }
        }
    }

    private func finish() {
        MenuBarTip.shared.hide()
        firstRun = false
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        guard AXIsProcessTrusted() else { return }
        HUD.shared.show("Tiling on", on: nil)
    }
}

// MARK: - Overlay plumbing

/// Borderless, transparent panel for the onboarding overlays. Most never become key, so keyboard
/// focus stays with the practice windows; `keyable` ones (cards that ask for an answer) take it so
/// Return reaches their default button, without activating the app. `clickThrough` lets the mouse
/// reach what's beneath.
final class OverlayPanel: NSPanel {
    private let keyable: Bool

    init(frame: NSRect, level: NSWindow.Level, clickThrough: Bool, keyable: Bool = false) {
        self.keyable = keyable
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        self.level = level
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }
    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

/// Our app is never active during onboarding, so controls must take the very first click.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

let easeOutBack = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)

func animate(_ duration: Double, curve: CAMediaTimingFunction = easeOutBack, changes: () -> Void,
             completion: (() -> Void)? = nil) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = duration
        ctx.timingFunction = curve
        ctx.allowsImplicitAnimation = true
        changes()
    }, completionHandler: completion)
}

private extension NSWindow.Level {
    static func above(_ l: NSWindow.Level, _ n: Int) -> NSWindow.Level { NSWindow.Level(rawValue: l.rawValue + n) }
}


// MARK: - Intro

/// The opening, played over the whole screen and drawn from the app icon: it dims to graphite, four
/// windows drift in (the main one in the icon's electric blue), snap into a tiling layout with a squish
/// and the icon's yellow impact lines, the wordmark lands, they re-tile, then fly into the welcome
/// card. Each tile is its own window. Click anywhere to skip.
private final class Intro {
    static let margin: CGFloat = 60 // room around each tile for its rotation and shadow

    private let screen: NSScreen
    private let landing: NSRect
    private let onDone: () -> Void
    private var dim: OverlayPanel!
    private var skipLabel: NSTextField!
    private var tiles: [OverlayPanel] = []
    private var word: OverlayPanel!
    private let wordModel = WordmarkModel()
    private var wordFrame = NSRect.zero
    private var pending: [DispatchWorkItem] = []
    private var stage = 0
    private var done = false

    init(screen: NSScreen, landing: NSRect, onDone: @escaping () -> Void) {
        self.screen = screen
        self.landing = landing
        self.onDone = onDone
        build()
    }

    func run() {
        dim.orderFrontRegardless()
        tiles.forEach { $0.orderFrontRegardless() }
        word.orderFrontRegardless()
        for (i, at) in [0.12, 1.25, 2.3, 3.55, 4.85].enumerated() {
            later(at) { [weak self] in self?.go(to: i + 1) }
        }
        later(5.6) { [weak self] in self?.finish() }
    }

    private func later(_ seconds: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        pending.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func skip() {
        guard !done, stage < 5 else { return }
        pending.forEach { $0.cancel() }
        pending = []
        if stage == 0 { go(to: 1) }
        go(to: 5)
        later(0.5) { [weak self] in self?.finish() }
    }

    private func finish() {
        guard !done else { return }
        done = true
        onDone()
        let panels = [dim!, word!] + tiles
        animate(0.7, curve: CAMediaTimingFunction(name: .easeOut), changes: { panels.forEach { $0.animator().alphaValue = 0 } }) {
            panels.forEach { $0.orderOut(nil) }
        }
    }

    // MARK: Building

    private func build() {
        let f = screen.frame
        dim = OverlayPanel(frame: f, level: .above(.statusBar, 1), clickThrough: false)
        let root = ClickView(frame: NSRect(origin: .zero, size: f.size))
        root.onClick = { [weak self] in self?.skip() }
        let blur = NSVisualEffectView(frame: root.bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        root.addSubview(blur)
        // Graphite from the icon, a little lighter in the middle so the tiles read as lit from the front.
        let shade = CAGradientLayer()
        shade.type = .radial
        shade.colors = [Intro.graphite.withAlphaComponent(0.3).cgColor, Intro.graphite.withAlphaComponent(0.62).cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0.5)
        shade.endPoint = CGPoint(x: 1.1, y: 1.1)
        let shadeView = NSView(frame: root.bounds)
        shadeView.autoresizingMask = [.width, .height]
        shadeView.wantsLayer = true
        shade.frame = shadeView.bounds
        shade.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        shadeView.layer?.addSublayer(shade)
        root.addSubview(shadeView)
        skipLabel = NSTextField(labelWithString: "Click anywhere to skip")
        skipLabel.font = Theme.nsBody(12)
        skipLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        skipLabel.sizeToFit()
        skipLabel.setFrameOrigin(NSPoint(x: f.width - skipLabel.frame.width - 20, y: 18))
        skipLabel.alphaValue = 0
        root.addSubview(skipLabel)
        dim.contentView = root
        dim.alphaValue = 0

        for i in 0..<4 {
            let p = OverlayPanel(frame: padded(start), level: .above(.statusBar, 2), clickThrough: true)
            p.contentView = TileView(frame: NSRect(origin: .zero, size: p.frame.size), main: i == 0)
            p.alphaValue = 0
            tiles.append(p)
        }

        let size = max(64, min(140, f.width * 0.11))
        wordFrame = NSRect(x: f.minX, y: f.midY - 150, width: f.width, height: 300)
        word = OverlayPanel(frame: wordFrame.offsetBy(dx: 0, dy: -24), level: .above(.statusBar, 3), clickThrough: true)
        word.contentView = NSHostingView(rootView: WordmarkView(model: wordModel, size: size))
        word.alphaValue = 0
    }

    static let graphite = NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1E / 255, alpha: 1)

    // MARK: Stages

    private var start: NSRect { NSRect(x: screen.frame.midX - 60, y: screen.frame.midY - 40, width: 120, height: 80) }

    private func padded(_ r: NSRect) -> NSRect { r.insetBy(dx: -Self.margin, dy: -Self.margin) }

    /// A rect given top-down as fractions of the screen, in AppKit coordinates.
    private func fraction(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        let f = screen.frame
        return NSRect(x: f.minX + x * f.width, y: f.maxY - (y + h) * f.height, width: w * f.width, height: h * f.height)
    }

    /// Tall or BSP frames for four tiles with gaps, like the real layouts.
    private func layout(bsp: Bool) -> [NSRect] {
        let f = screen.frame.insetBy(dx: 28, dy: 28)
        let gap: CGFloat = 18
        var out: [NSRect] = []
        // Work top-down, then flip into AppKit coordinates.
        var r = CGRect(x: 0, y: 0, width: f.width + gap, height: f.height + gap)
        if bsp {
            for i in 0..<3 {
                if i % 2 == 0 {
                    out.append(CGRect(x: r.minX, y: r.minY, width: r.width / 2, height: r.height))
                    r = CGRect(x: r.minX + r.width / 2, y: r.minY, width: r.width / 2, height: r.height)
                } else {
                    out.append(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height / 2))
                    r = CGRect(x: r.minX, y: r.minY + r.height / 2, width: r.width, height: r.height / 2)
                }
            }
            out.append(r)
        } else {
            let main = r.width / 2, h = r.height / 3
            out.append(CGRect(x: 0, y: 0, width: main, height: r.height))
            for i in 0..<3 { out.append(CGRect(x: main, y: CGFloat(i) * h, width: r.width - main, height: h)) }
        }
        return out.map { t in
            let g = t.insetBy(dx: gap / 2, dy: gap / 2)
            return NSRect(x: f.minX + g.minX, y: f.maxY - g.maxY, width: g.width, height: g.height).integral
        }
    }

    private func go(to s: Int) {
        guard s > stage else { return }
        stage = s
        let scatter: [(NSRect, CGFloat)] = [(fraction(0.1, 0.16, 0.26, 0.3), -9), (fraction(0.62, 0.1, 0.25, 0.28), 7),
                                            (fraction(0.16, 0.58, 0.22, 0.27), 6), (fraction(0.6, 0.56, 0.28, 0.31), -6)]
        let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.15, 1)
        func tile(_ i: Int) -> TileView? { tiles[i].contentView as? TileView }
        func move(_ i: Int, to r: NSRect, alpha: CGFloat, rotation: CGFloat, duration: Double, delay: Double) {
            let p = tiles[i]
            let run = {
                tile(i)?.rotate(to: rotation, duration: duration, curve: curve)
                animate(duration, curve: curve) { p.animator().setFrame(self.padded(r), display: true) }
                animate(0.6, curve: CAMediaTimingFunction(name: .easeOut)) { p.animator().alphaValue = alpha }
            }
            if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: run) } else { run() }
        }
        /// When a tile lands: it squishes, and the main one takes the icon's impact lines.
        func land(_ i: Int, after delay: Double, spark: Bool) {
            later(delay) {
                tile(i)?.squish()
                if spark { tile(i)?.spark() }
            }
        }
        switch s {
        case 1:
            animate(1, curve: CAMediaTimingFunction(name: .easeOut)) {
                dim.animator().alphaValue = 1
                skipLabel.animator().alphaValue = 1
            }
            for (i, t) in scatter.enumerated() {
                tile(i)?.rotate(to: t.1 * 2, duration: 0, curve: curve)
                move(i, to: t.0, alpha: 1, rotation: t.1, duration: 1.1, delay: Double(i) * 0.07)
            }
        case 2:
            for (i, r) in layout(bsp: false).enumerated() {
                let delay = Double(i) * 0.07
                move(i, to: r, alpha: 1, rotation: 0, duration: 0.8, delay: delay)
                land(i, after: delay + 0.36, spark: i == 0)
            }
        case 3:
            // Low enough that the tagline reads over the blue main tile.
            for i in tiles.indices { animate(0.6) { tiles[i].animator().alphaValue = i == 0 ? 0.4 : 0.3 } }
            wordModel.landed = true
            animate(1.1) {
                word.animator().alphaValue = 1
                word.animator().setFrame(wordFrame, display: true)
            }
        case 4:
            for (i, r) in layout(bsp: true).enumerated() {
                let delay = Double(i) * 0.05
                move(i, to: r, alpha: i == 0 ? 0.4 : 0.3, rotation: 0, duration: 0.9, delay: delay)
                land(i, after: delay + 0.4, spark: false)
            }
            wordModel.subtitle = true
        default:
            for i in tiles.indices { move(i, to: landing, alpha: 0, rotation: 0, duration: 0.7, delay: Double(i) * 0.03) }
            animate(0.9, curve: CAMediaTimingFunction(name: .easeOut)) {
                word.animator().alphaValue = 0
                skipLabel.animator().alphaValue = 0
            }
        }
    }
}

/// Full-screen backdrop that reports a click anywhere.
private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}

/// One tile of the intro: a translucent window with three dots, drawn inside its panel with some
/// margin so it can be rotated. The main tile is filled with the icon's electric blue.
private final class TileView: NSView {
    private let card = CALayer()
    private let sheen = CAGradientLayer()
    private var dots: [CALayer] = []
    private let lines = CAShapeLayer()
    private let main: Bool

    init(frame: NSRect, main: Bool) {
        self.main = main
        super.init(frame: frame)
        wantsLayer = true
        card.backgroundColor = main ? NSColor(srgbRed: 0x0A / 255, green: 0x74 / 255, blue: 1, alpha: 0.92).cgColor
                                    : NSColor(white: 1, alpha: 0.13).cgColor
        card.borderColor = NSColor(white: 1, alpha: main ? 0.5 : 0.38).cgColor
        card.borderWidth = 1
        card.cornerRadius = 14
        card.cornerCurve = .continuous
        card.shadowColor = (main ? NSColor(srgbRed: 0x0A / 255, green: 0x74 / 255, blue: 1, alpha: 1) : .black).cgColor
        card.shadowOpacity = main ? 0.35 : 0.25
        card.shadowRadius = 24
        card.shadowOffset = CGSize(width: 0, height: -16)
        // A soft light across the top, like glass catching it.
        sheen.colors = [NSColor(white: 1, alpha: main ? 0.22 : 0.12).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        sheen.startPoint = CGPoint(x: 0.5, y: 1)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.55)
        sheen.cornerRadius = 14
        sheen.cornerCurve = .continuous
        sheen.masksToBounds = true
        card.addSublayer(sheen)
        for a in [0.55, 0.35, 0.25] {
            let d = CALayer()
            d.backgroundColor = NSColor(white: 1, alpha: main ? a + 0.25 : a).cgColor
            d.cornerRadius = 4.5
            card.addSublayer(d)
            dots.append(d)
        }
        layer?.addSublayer(card)
        lines.strokeColor = NSColor(srgbRed: 1, green: 0xCC / 255, blue: 0, alpha: 1).cgColor // the icon's spark yellow
        lines.fillColor = nil
        lines.lineWidth = 4
        lines.lineCap = .round
        lines.opacity = 0
        layer?.addSublayer(lines)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = bounds.insetBy(dx: Intro.margin, dy: Intro.margin)
        card.bounds = CGRect(origin: .zero, size: CGSize(width: max(0, r.width), height: max(0, r.height)))
        card.position = CGPoint(x: r.midX, y: r.midY)
        sheen.frame = card.bounds
        for (i, d) in dots.enumerated() {
            d.frame = CGRect(x: 12 + CGFloat(i) * 15, y: card.bounds.height - 11 - 9, width: 9, height: 9)
        }
        // The impact lines sit off the top-left corner, pointing away from it.
        let c = CGPoint(x: r.minX - 4, y: r.maxY + 4), radius: CGFloat = 30
        let path = CGMutablePath()
        for (spread, reach) in [(-40.0, 0.78), (0, 1), (40, 0.78)] {
            let a = (135 + spread) * .pi / 180
            path.move(to: CGPoint(x: c.x + cos(a) * radius * 0.4, y: c.y + sin(a) * radius * 0.4))
            path.addLine(to: CGPoint(x: c.x + cos(a) * radius * reach, y: c.y + sin(a) * radius * reach))
        }
        lines.frame = bounds
        lines.path = path
        CATransaction.commit()
    }

    /// Degrees clockwise, as in CSS.
    func rotate(to degrees: CGFloat, duration: Double, curve: CAMediaTimingFunction) {
        CATransaction.begin()
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(curve)
        card.setAffineTransform(CGAffineTransform(rotationAngle: -degrees * .pi / 180))
        CATransaction.commit()
    }

    /// A quick squash and stretch, like a window hitting the edge of its slot.
    func squish() {
        for (key, values) in [("transform.scale.x", [1, 1.035, 0.99, 1]), ("transform.scale.y", [1, 0.955, 1.01, 1])] {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = values
            a.keyTimes = [0, 0.3, 0.7, 1]
            a.duration = 0.42
            a.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                                 CAMediaTimingFunction(name: .easeOut)]
            card.add(a, forKey: key)
        }
    }

    /// The icon's three yellow lines flash out from the corner.
    func spark() {
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = 0.18
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.1, 0.6, 1]
        fade.duration = 0.7
        lines.add(draw, forKey: "draw")
        lines.add(fade, forKey: "fade")
    }
}
