import AppKit
import CatWMKit
import SwiftUI

final class Onboarding {
    static let shared = Onboarding()
    static let doneKey = "didOnboard"

    static let startedKey = "onboardingStarted"

    static var isDone: Bool { Instance.defaults.bool(forKey: doneKey) }
    static var isStarted: Bool { Instance.defaults.bool(forKey: startedKey) }

    weak var statusButton: NSStatusBarButton? {
        didSet { MenuBarTip.shared.statusButton = statusButton }
    }
    var intro: Intro?
    var welcome: CatWMPanel?
    let welcomeModel = WelcomeModel()
    var poll: Timer?
    var coach: Coach?
    var openedLoginItems = false
    var offering = false
    var firstRun = false

    var isRunning: Bool { intro != nil || welcome != nil || coach != nil || offering }
}

extension Onboarding {
    func startTutorial(fromStart: Bool = false) {
        if fromStart, canRun { TutorialLesson.forget() }
        run(TutorialLesson()) { how in
            switch how {
            case .paused:
                let chapter = TutorialLesson.paused?.name
                HUD.shared.show(chapter.map { "Paused at \($0)" } ?? "Tutorial paused", on: nil)
            case .finished, .tutorial:
                HUD.shared.show("Tutorial complete", on: nil)
            case .skipped:
                break
            }
        }
    }

    var canRun: Bool { coach == nil && intro == nil && welcome == nil }

    func run(_ lesson: Lesson, attempts: Int = 20, then: @escaping (Coach.Ending) -> Void) {
        guard canRun else { return }
        guard WindowManager.shared.isStarted, Hotkeys.shared.isActive else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.run(lesson, attempts: attempts - 1, then: then)
                }
            } else {
                HUD.shared.show("CatWM needs Accessibility first", on: nil)
                MenuBarTip.shared.hide()
                if firstRun, Permission.accessibility.isGranted {
                    Instance.defaults.set(true, forKey: Self.doneKey)
                }
                firstRun = false
            }
            return
        }
        Tips.shared.dismissAll()
        if SortPanel.shared.isOpen { SortPanel.shared.revert() }
        guard let started = Coach(lesson: lesson, statusButton: statusButton, onEnd: { [weak self] how in
            self?.coach = nil
            then(how)
        }) else { return }
        coach = started
        started.start()
        if firstRun { MenuBarTip.shared.show() }
    }

    func offerSort(then: @escaping () -> Void) {
        let windowManager = WindowManager.shared
        let nudge = windowManager.config.sortNudge
        guard nudge > 0, let hit = windowManager.shownWorkspaces().first, hit.count > nudge else { return then() }
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

    func finish() {
        MenuBarTip.shared.hide()
        firstRun = false
        Instance.defaults.set(true, forKey: Self.doneKey)
        guard Permission.accessibility.isGranted else { return }
        HUD.shared.show("Tiling on", on: nil)
    }
}
