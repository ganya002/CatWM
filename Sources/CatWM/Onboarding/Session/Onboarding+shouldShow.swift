import AppKit
import CatWMKit
import SwiftUI

extension Onboarding {
    static func shouldShow(firstRun: Bool, trusted: Bool, done: Bool = isDone, started: Bool = isStarted) -> Bool {
        !done && (firstRun || !trusted || started)
    }

    func start() {
        guard !isRunning else { return }
        let resuming = Self.isStarted && !LaunchFlag.onboarding.isSet
        firstRun = true
        Instance.defaults.set(true, forKey: Self.startedKey)
        guard let screen = CatWMPanel.pointerScreen() else { return }
        let card = makeWelcome(on: screen)
        guard !resuming, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return showWelcome() }
        let margin = WelcomeView.margin
        let intro = Intro(screen: screen, landing: card.frame.insetBy(dx: margin, dy: margin)) { [weak self] in
            self?.intro = nil
            self?.showWelcome()
        }
        self.intro = intro
        intro.run()
    }

    func playIntro(_ arrangement: IntroScore.Arrangement = .standard) {
        guard !isRunning, let screen = CatWMPanel.pointerScreen() else { return }
        let visible = screen.visibleFrame
        let landing = NSRect(x: visible.midX - 230, y: visible.midY - 200, width: 460, height: 400)
        let intro = Intro(screen: screen, landing: landing, music: arrangement) { [weak self] in self?.intro = nil }
        self.intro = intro
        intro.run()
    }

    func makeWelcome(on screen: NSScreen) -> CatWMPanel {
        welcomeModel.page = .permissions
        welcomeModel.style = KeyStyle.current
        welcomeModel.allowAccessibility = { Permission.accessibility.request() }
        welcomeModel.allowInputMonitoring = { Permission.inputMonitoring.request() }
        welcomeModel.allowScreenRecording = { Permission.screenRecording.request() }
        welcomeModel.allowFullDiskAccess = { Permission.fullDiskAccess.request() }
        welcomeModel.takeTestImage = { [weak self] in
            Task { @MainActor in
                guard await ScreenRecording.shared.takeTestImage() else { return }
                self?.welcomeModel.screenTestDone = true
                self?.welcome?.makeKeyAndOrderFront(nil)
            }
        }
        welcomeModel.allowLogin = { [weak self] in
            LoginItem.shared.set(true)
            if !LoginItem.shared.isEnabled {
                self?.openedLoginItems = true
                LoginItem.shared.openSettings()
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
        let host = CatWMHostingView(rootView: WelcomeView(model: welcomeModel))
        let panel = CatWMPanel(role: .card(.normal),
                              frame: CatWMPanel.frame(size: host.fittingSize, on: screen, anchor: .center(dy: -12),
                                                     inset: EdgeInsets(all: WelcomeView.margin)))
        panel.onClose = { [weak self] in self?.welcomeModel.skip() }
        panel.contentView = host
        panel.isMovableByWindowBackground = true
        welcome = panel
        return panel
    }

    func refreshWelcome() {
        let accessibility = Permission.accessibility.isGranted, login = LoginItem.shared.isEnabled
        if welcomeModel.accessibility != accessibility { welcomeModel.accessibility = accessibility }
        let inputMonitoring = Permission.inputMonitoring.isGranted
        if welcomeModel.inputMonitoring != inputMonitoring { welcomeModel.inputMonitoring = inputMonitoring }
        let screenRecording = Permission.screenRecording.isGranted, screenTestDone = ScreenRecording.shared.isTestDone
        if welcomeModel.screenRecording != screenRecording { welcomeModel.screenRecording = screenRecording }
        if welcomeModel.screenTestDone != screenTestDone { welcomeModel.screenTestDone = screenTestDone }
        let fullDiskAccess = Permission.fullDiskAccess.isGranted
        if welcomeModel.fullDiskAccess != fullDiskAccess { welcomeModel.fullDiskAccess = fullDiskAccess }
        if welcomeModel.login != login { welcomeModel.login = login }
        if login, openedLoginItems {
            openedLoginItems = false
            if accessibility { Permission.closeSettingsWindows() }
            welcome?.makeKeyAndOrderFront(nil)
        }
    }

    func showWelcome() {
        guard let panel = welcome else { return }
        let end = panel.frame
        welcomeModel.landed = false
        panel.alphaValue = 0
        panel.setFrame(end.offsetBy(dx: 0, dy: -14), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        Motion.group(0.5) {
            Motion.setAlpha(1, on: panel)
            Motion.setFrame(end, on: panel)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.welcomeModel.landed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            if self?.isRunning == true { MenuBarTip.shared.show() }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            LoginItem.shared.refresh { self?.refreshWelcome() }
        }
        poll?.tolerance = 0.1
    }

    func hideWelcome(then: @escaping () -> Void) {
        poll?.invalidate()
        poll = nil
        PermissionGuide.shared.onGranted = nil
        guard let panel = welcome else { return then() }
        welcome = nil
        Motion.group(0.3, changes: { Motion.setAlpha(0, on: panel) }, completion: {
            panel.orderOut(nil)
            then()
        })
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
