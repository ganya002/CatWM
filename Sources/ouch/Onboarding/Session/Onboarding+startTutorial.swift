import AppKit
import SwiftUI

extension Onboarding {
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

    func run(_ lesson: Lesson, attempts: Int = 20, then: @escaping (Coach.Ending) -> Void) {
        guard coach == nil, intro == nil, welcome == nil else { return }
        guard WindowManager.shared.isStarted, Hotkeys.shared.isActive else {
            if attempts > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.run(lesson, attempts: attempts - 1, then: then) }
            } else {
                HUD.shared.show("Ouch needs Accessibility first", on: nil)
                MenuBarTip.shared.hide()
                if firstRun, Permission.accessibility.isGranted { UserDefaults.standard.set(true, forKey: Self.doneKey) }
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

    func offerSort(then: @escaping () -> Void) {
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

    func finish() {
        MenuBarTip.shared.hide()
        firstRun = false
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        guard Permission.accessibility.isGranted else { return }
        HUD.shared.show("Tiling on", on: nil)
    }
}
