import AppKit
import SwiftUI

extension Onboarding {
    static func shouldShow(firstRun: Bool, trusted: Bool) -> Bool {
        !isDone && (firstRun || !trusted)
    }

    func start() {
        guard !isRunning else { return }
        firstRun = true
        let screen = OuchPanel.pointerScreen()
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
        let screen = OuchPanel.pointerScreen()
        let v = screen.visibleFrame
        let landing = NSRect(x: v.midX - 230, y: v.midY - 200, width: 460, height: 400)
        let intro = Intro(screen: screen, landing: landing, music: arrangement) { [weak self] in self?.intro = nil }
        self.intro = intro
        intro.run()
    }

    func makeWelcome(on screen: NSScreen) -> OuchPanel {
        welcomeModel.page = .permissions
        welcomeModel.style = KeyStyle.current
        welcomeModel.allowAccessibility = { Permission.accessibility.request() }
        welcomeModel.allowInputMonitoring = { Permission.inputMonitoring.request() }
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
            guard Permission.accessibility.isGranted else { Permission.accessibility.request(); return }
            self?.welcomeModel.page = .keys
        }
        welcomeModel.start = { [weak self] in
            guard let self else { return }
            guard Permission.accessibility.isGranted else { welcomeModel.page = .permissions; return }
            if let style = welcomeModel.style, style != KeyStyle.current,
               let config = SettingsWindow.shared.library.config(id: style.configID) {
                SettingsWindow.shared.library.select(config)
            }
            hideWelcome { self.startTour() }
        }
        refreshWelcome()
        let host = OuchHostingView(rootView: WelcomeView(model: welcomeModel))
        let p = OuchPanel(role: .card(.normal),
                          frame: OuchPanel.frame(size: host.fittingSize, on: screen, anchor: .center(dy: -12),
                                                 inset: EdgeInsets(all: WelcomeView.margin)))
        p.onClose = { [weak self] in self?.welcomeModel.skip() }
        p.contentView = host
        p.isMovableByWindowBackground = true
        welcome = p
        return p
    }

    func refreshWelcome() {
        let ax = Permission.accessibility.isGranted, login = LoginItem.isEnabled
        if welcomeModel.accessibility != ax { welcomeModel.accessibility = ax }
        let im = Permission.inputMonitoring.isGranted
        if welcomeModel.inputMonitoring != im { welcomeModel.inputMonitoring = im }
        if welcomeModel.login != login { welcomeModel.login = login }
        if login, openedLoginItems {
            openedLoginItems = false
            if ax { Permission.closeSettingsWindows() }
            welcome?.makeKeyAndOrderFront(nil)
        }
    }

    func showWelcome() {
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

    func hideWelcome(then: @escaping () -> Void) {
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

}
