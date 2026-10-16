import AppKit
import SwiftUI

final class Onboarding {
    static let shared = Onboarding()
    private static let doneKey = "didOnboard"

    static var isDone: Bool { UserDefaults.standard.bool(forKey: doneKey) }

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
    private var firstRun = false

    var isRunning: Bool { intro != nil || welcome != nil || coach != nil || offering }

    static func shouldShow(firstRun: Bool, trusted: Bool) -> Bool {
        !isDone && (firstRun || !trusted)
    }

    func start() {
        guard !isRunning else { return }
        firstRun = true
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let card = makeWelcome(on: screen)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return showWelcome() }
        let m = WelcomeView.margin
        let intro = Intro(screen: screen, landing: card.frame.insetBy(dx: m, dy: m)) { [weak self] in
            self?.intro = nil
            self?.showWelcome()
        }
        self.intro = intro
        intro.run()
    }

    func playIntro(_ arrangement: IntroScore.Arrangement = .standard) {
        guard !isRunning else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let v = screen.visibleFrame
        let landing = NSRect(x: v.midX - 230, y: v.midY - 200, width: 460, height: 400)
        let intro = Intro(screen: screen, landing: landing, music: arrangement) { [weak self] in self?.intro = nil }
        self.intro = intro
        intro.run()
    }


    private func makeWelcome(on screen: NSScreen) -> OverlayPanel {
        welcomeModel.page = .permissions
        welcomeModel.style = KeyStyle.current
        welcomeModel.allowAccessibility = { Permissions.request() }
        welcomeModel.allowInputMonitoring = { Permissions.requestInputMonitoring() }
        welcomeModel.allowLogin = { [weak self] in
            LoginItem.set(true)
            if !LoginItem.isEnabled {
                self?.openedLoginItems = true
                LoginItem.openSettings()
            }
        }
        PermissionGuide.shared.onGranted = { [weak self] in self?.welcome?.makeKeyAndOrderFront(nil) }
        welcomeModel.skip = { [weak self] in self?.hideWelcome { self?.finish() } }
        welcomeModel.next = { [weak self] in
            guard AXIsProcessTrusted() else { Permissions.request(); return }
            self?.welcomeModel.page = .keys
        }
        welcomeModel.start = { [weak self] in
            guard let self else { return }
            guard AXIsProcessTrusted() else { welcomeModel.page = .permissions; return }
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
        p.makeKey()
        p.invalidateShadow()
        animate(0.5) {
            p.animator().alphaValue = 1
            p.animator().setFrame(end, display: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.welcomeModel.landed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.isRunning == true { MenuBarTip.shared.show() }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshWelcome() }
        poll?.tolerance = 0.1
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


    func startTour() {
        let lesson = TourLesson()
        run(lesson) { [weak self] how in
            guard let self else { return }
            if how == .tutorial {
                finish()
                startTutorial()
            } else {
                offerSort { self.finish() }
            }
        }
    }

    func startTutorial(fromStart: Bool = false) {
        if fromStart { TutorialLesson.forget() }
        run(TutorialLesson()) { how in
            switch how {
            case .paused:
                let at = TutorialLesson.paused?.name
                HUD.shared.show(at.map { "Paused at \($0)" } ?? "Tutorial paused", on: nil)
            case .finished, .tutorial:
                HUD.shared.show("Tutorial complete", on: nil)
            case .skipped:
                break
            }
        }
    }

    private func run(_ lesson: Lesson, attempts: Int = 20, then: @escaping (Coach.Ending) -> Void) {
        guard coach == nil, intro == nil, welcome == nil else { return }
        guard WindowManager.shared.isStarted, Hotkeys.shared.isActive else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.run(lesson, attempts: attempts - 1, then: then) }
            } else {
                HUD.shared.show("Ouch needs Accessibility first", on: nil)
                MenuBarTip.shared.hide()
                if firstRun, AXIsProcessTrusted() { UserDefaults.standard.set(true, forKey: Self.doneKey) }
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

    private func offerSort(then: @escaping () -> Void) {
        let wm = WindowManager.shared
        guard wm.config.sortNudge > 0, let hit = wm.shownWorkspaces().first, hit.count > wm.config.sortNudge else { return then() }
        offering = true
        MenuBarTip.shared.suppressed = true
        SortNudge.shared.markOffered(hit.workspace)
        SortOffer.shared.show(button: statusButton, on: hit.screen) { [weak self] sort in
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

final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

let easeOutBack = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)

func animate(_ duration: Double, curve: CAMediaTimingFunction = easeOutBack, label: String = #fileID,
             changes: () -> Void, completion: (() -> Void)? = nil) {
    PerfMonitor.track("ui:" + label, for: duration)
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



private final class Intro {
    static let margin: CGFloat = 60
    static let count = 5

    private let screen: NSScreen
    private let landing: NSRect
    private let onDone: () -> Void
    private let score: IntroScore
    private var dim: OverlayPanel!
    private var skipLabel: NSTextField!
    private var tiles: [OverlayPanel] = []
    private var word: OverlayPanel!
    private var fx: OverlayPanel!
    private let wordModel = WordmarkModel()
    private var wordFrame = NSRect.zero
    private var pending: [DispatchWorkItem] = []
    private var done = false

    private let curve = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.15, 1)

    init(screen: NSScreen, landing: NSRect, music: IntroScore.Arrangement = .standard, onDone: @escaping () -> Void) {
        self.screen = screen
        self.landing = landing
        self.onDone = onDone
        score = IntroScore(music)
        build()
    }

    func run() {
        dim.orderFrontRegardless()
        tiles.forEach { $0.orderFrontRegardless() }
        word.orderFrontRegardless()
        fx.orderFrontRegardless()
        score.play()
        typealias B = IntroScore.Beat
        fadeIn()
        for (i, t) in B.arrive.enumerated() { later(t - 0.12) { [weak self] in self?.arrive(i + 1) } }
        later(B.word - 0.25) { [weak self] in self?.showWord() }
        later(B.retile - 0.1) { [weak self] in self?.retile() }
        later(B.gather) { [weak self] in self?.gather() }
        later(B.impact - 0.06) { [weak self] in self?.impact() }
    }

    private func later(_ seconds: Double, _ f: @escaping () -> Void) {
        let w = DispatchWorkItem(block: f)
        pending.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func skip() {
        guard !done else { return }
        pending.forEach { $0.cancel() }
        pending = []
        score.fadeOut()
        fadeIn()
        for i in tiles.indices { move(i, to: landing, alpha: 0, duration: 0.7, delay: Double(i) * 0.03) }
        hideWord()
        later(0.5) { [weak self] in self?.finish(over: 0.7) }
    }

    private func finish(over seconds: Double) {
        guard !done else { return }
        done = true
        onDone()
        let panels = [dim!, word!] + tiles
        animate(seconds, curve: CAMediaTimingFunction(name: .easeOut), changes: { panels.forEach { $0.animator().alphaValue = 0 } }) {
            panels.forEach { $0.orderOut(nil) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [fx] in fx?.orderOut(nil) }
    }


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

        let center = NSRect(x: f.midX, y: f.midY, width: 0, height: 0)
        for i in 0..<Self.count {
            let p = OverlayPanel(frame: padded(center), level: .above(.statusBar, 2), clickThrough: true)
            p.contentView = TileView(frame: NSRect(origin: .zero, size: p.frame.size), main: i == 0)
            p.alphaValue = 0
            tiles.append(p)
        }

        let size = max(64, min(140, f.width * 0.11))
        wordFrame = NSRect(x: f.minX, y: f.midY - 150, width: f.width, height: 300)
        word = OverlayPanel(frame: wordFrame.offsetBy(dx: 0, dy: -24), level: .above(.statusBar, 3), clickThrough: true)
        word.contentView = NSHostingView(rootView: WordmarkView(model: wordModel, size: size))
        word.alphaValue = 0

        fx = OverlayPanel(frame: f, level: .above(.statusBar, 4), clickThrough: true)
        fx.contentView = ImpactView(frame: NSRect(origin: .zero, size: f.size))
    }

    static let graphite = NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1E / 255, alpha: 1)


    private func tile(_ i: Int) -> TileView? { tiles.indices.contains(i) ? tiles[i].contentView as? TileView : nil }

    private func padded(_ r: NSRect) -> NSRect { r.insetBy(dx: -Self.margin, dy: -Self.margin) }

    private func move(_ i: Int, to r: NSRect, alpha: CGFloat, duration: Double, delay: Double = 0,
                      curve: CAMediaTimingFunction? = nil) {
        let p = tiles[i], c = curve ?? self.curve
        let run = {
            animate(duration, curve: c) { p.animator().setFrame(self.padded(r), display: true) }
            animate(min(duration, 0.4), curve: CAMediaTimingFunction(name: .easeOut)) { p.animator().alphaValue = alpha }
        }
        if delay > 0 { later(delay, run) } else { run() }
    }

    private func layout(bsp: Bool, _ n: Int = Intro.count) -> [NSRect] {
        let f = screen.frame.insetBy(dx: 28, dy: 28)
        let gap: CGFloat = 18
        var out: [NSRect] = []
        var r = CGRect(x: 0, y: 0, width: f.width + gap, height: f.height + gap)
        if bsp || n == 1 {
            for i in 0..<(n - 1) {
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
            let main = r.width / 2, h = r.height / CGFloat(n - 1)
            out.append(CGRect(x: 0, y: 0, width: main, height: r.height))
            for i in 0..<(n - 1) { out.append(CGRect(x: main, y: CGFloat(i) * h, width: r.width - main, height: h)) }
        }
        return out.map { t in
            let g = t.insetBy(dx: gap / 2, dy: gap / 2)
            return NSRect(x: f.minX + g.minX, y: f.maxY - g.maxY, width: g.width, height: g.height).integral
        }
    }

    private func fadeIn() {
        animate(0.8, curve: CAMediaTimingFunction(name: .easeOut)) {
            dim.animator().alphaValue = 1
            skipLabel.animator().alphaValue = 1
        }
    }

    private func arrive(_ n: Int) {
        let frames = layout(bsp: true, n)
        for i in 0..<(n - 1) {
            move(i, to: frames[i], alpha: 1, duration: 0.45)
            later(0.12) { [weak self] in self?.tile(i)?.squish() }
        }
        let i = n - 1, slot = frames[i]
        tiles[i].setFrame(padded(slot.insetBy(dx: slot.width * 0.3, dy: slot.height * 0.3)), display: false)
        move(i, to: slot, alpha: 1, duration: 0.45)
        later(0.12) { [weak self] in self?.tile(i)?.squish() }
    }

    private func showWord() {
        for i in tiles.indices { animate(0.5) { tiles[i].animator().alphaValue = i == 0 ? 0.4 : 0.3 } }
        wordModel.landed = true
        animate(1.1) {
            word.animator().alphaValue = 1
            word.animator().setFrame(wordFrame, display: true)
        }
    }

    private func hideWord() {
        animate(0.5, curve: CAMediaTimingFunction(name: .easeOut)) {
            word.animator().alphaValue = 0
            skipLabel.animator().alphaValue = 0
        }
    }

    private func retile() {
        wordModel.subtitle = true
        let step = IntroScore.Beat.step
        for (i, r) in layout(bsp: false).enumerated() {
            move(i, to: r, alpha: i == 0 ? 0.4 : 0.3, duration: 0.6, delay: Double(i) * step)
            later(Double(i) * step + 0.1) { [weak self] in self?.tile(i)?.squish() }
        }
    }

    private func gather() {
        hideWord()
        let span = IntroScore.Beat.impact - 0.25 - IntroScore.Beat.gather
        let c = NSPoint(x: landing.midX, y: landing.midY)
        let w = landing.width * 0.42, h = landing.height * 0.42
        let pull = CAMediaTimingFunction(controlPoints: 0.6, 0, 0.2, 1)
        for i in tiles.indices.reversed() {
            let o = CGFloat(i) * 7
            let r = NSRect(x: c.x - w / 2 + o, y: c.y - h / 2 - o, width: w, height: h)
            move(i, to: r, alpha: i == 0 ? 1 : 0.85, duration: span, delay: Double(Self.count - 1 - i) * 0.04, curve: pull)
            tiles[i].order(.above, relativeTo: i == Self.count - 1 ? 0 : tiles[i + 1].windowNumber)
        }
        later(span) { [weak self] in self?.tiles.indices.forEach { self?.tile($0)?.brace() } }
    }

    private func impact() {
        guard !done else { return }
        pending.forEach { $0.cancel() }
        pending = []
        (fx.contentView as? ImpactView)?.fire(at: NSPoint(x: landing.midX - screen.frame.minX, y: landing.midY - screen.frame.minY))
        let burst = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.2, 1)
        for i in tiles.indices {
            let spread = CGFloat(i) * 10
            move(i, to: landing.insetBy(dx: -spread, dy: -spread), alpha: 0, duration: 0.6, curve: burst)
        }
        finish(over: 1.1)
    }
}

private final class ClickView: NSView {
    var onClick: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
}

private final class ImpactView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    func fire(at c: NSPoint) {
        guard let root = layer else { return }
        let flash = CALayer()
        flash.frame = bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 0.22, 0]
        blink.keyTimes = [0, 0.08, 1]
        blink.duration = 0.7
        blink.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeOut)]
        flash.add(blink, forKey: "blink")

        let reach = hypot(max(c.x, bounds.width - c.x), max(c.y, bounds.height - c.y)) * 1.1
        for (i, (color, width)) in [(NSColor.white, 3.0), (NSColor(srgbRed: 0x0A / 255, green: 0x74 / 255, blue: 1, alpha: 1), 10.0)].enumerated() {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2), transform: nil)
            ring.position = c
            ring.fillColor = nil
            ring.strokeColor = color.cgColor
            ring.lineWidth = width
            ring.opacity = 0
            ring.shadowColor = color.cgColor
            ring.shadowRadius = 18
            ring.shadowOpacity = 0.9
            root.addSublayer(ring)
            let delay = Double(i) * 0.08
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.04
            grow.toValue = 1
            grow.duration = 1.2
            grow.beginTime = CACurrentMediaTime() + delay
            grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.7, 0.3, 1)
            grow.fillMode = .both
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.95, 0]
            fade.keyTimes = [0, 0.05, 1]
            fade.duration = 1.2
            fade.beginTime = grow.beginTime
            fade.fillMode = .both
            ring.add(grow, forKey: "grow")
            ring.add(fade, forKey: "fade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { root.sublayers?.forEach { $0.removeFromSuperlayer() } }
    }
}

private final class TileView: NSView {
    private let card = CALayer()
    private let sheen = CAGradientLayer()
    private var dots: [CALayer] = []
    private let main: Bool

    private static let blue = NSColor(srgbRed: 0x0A / 255, green: 0x74 / 255, blue: 1, alpha: 1)

    init(frame: NSRect, main: Bool) {
        self.main = main
        super.init(frame: frame)
        wantsLayer = true
        card.backgroundColor = main ? Self.blue.withAlphaComponent(0.92).cgColor : NSColor(white: 1, alpha: 0.13).cgColor
        card.borderColor = NSColor(white: 1, alpha: main ? 0.5 : 0.38).cgColor
        card.borderWidth = 1
        card.cornerRadius = 14
        card.cornerCurve = .continuous
        card.shadowColor = (main ? Self.blue : .black).cgColor
        card.shadowOpacity = main ? 0.35 : 0.25
        card.shadowRadius = 24
        card.shadowOffset = CGSize(width: 0, height: -16)
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
        CATransaction.commit()
    }

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

    func brace() {
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.92
        shrink.duration = 0.25
        shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        card.add(shrink, forKey: "brace")
        let glow = CABasicAnimation(keyPath: "shadowRadius")
        glow.toValue = 48
        glow.duration = 0.25
        glow.fillMode = .forwards
        glow.isRemovedOnCompletion = false
        card.add(glow, forKey: "glow")
    }
}
