import AppKit
import SwiftUI

extension Onboarding {
    func startTutorial(fromStart: Bool = false) {
        if fromStart { TutorialLesson.forget() }
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

    func run(_ lesson: Lesson, attempts: Int = 20, then: @escaping (Coach.Ending) -> Void) {
        guard coach == nil, intro == nil, welcome == nil else { return }
        guard WindowManager.shared.isStarted, Hotkeys.shared.isActive else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.run(lesson, attempts: attempts - 1, then: then)
                }
            } else {
                HUD.shared.show("Ouch needs Accessibility first", on: nil)
                MenuBarTip.shared.hide()
                if firstRun, Permission.accessibility.isGranted {
                    UserDefaults.standard.set(true, forKey: Self.doneKey)
                }
                firstRun = false
            }
            return
        }
        Tips.shared.dismissAll()
        if SortPanel.shared.isOpen { SortPanel.shared.revert() }
        let started = Coach(lesson: lesson, statusButton: statusButton) { [weak self] how in
            self?.coach = nil
            then(how)
        }
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
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        guard Permission.accessibility.isGranted else { return }
        HUD.shared.show("Tiling on", on: nil)
    }
}
