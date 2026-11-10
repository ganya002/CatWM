import AppKit
import CatWMKit
import SwiftUI

extension Tips {
    func markSeen(_ id: String) {
        guard !seen.contains(id) else { return }
        defaults.set(Array(seen.union([id])), forKey: Self.seenKey)
    }

    func markSeen(_ known: Known) { markSeen(known.rawValue) }

    func launched() {
        _ = daysUsed
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            if !TutorialLesson.finishedOnce, TutorialLesson.paused == nil { self?.show(.tutorial) }
        }
    }

    func canShow(_ id: String) -> Bool {
        enabled && daysUsed >= Self.minDaysUsed && rested && Onboarding.isDone && !Onboarding.shared.isRunning
            && !seen.contains(id) && settings == nil && global == nil
            && !SortPanel.shared.isOpen && !WhatsNew.shared.isOpen
    }

    func show(_ known: Known) {
        switch known {
        case .tutorial:
            guard canShow(known.rawValue) else { return }
            present(Tip(id: known.rawValue, title: "Make the keys stick",
                        body: "Keyboard Tutorial, in this menu, drills them a chapter at a time.",
                        place: .menuBar, action: ("Start tutorial", { Onboarding.shared.startTutorial() })))
        case .keyHelp:
            let keys = ShortcutIndex()
            guard canShow(known.rawValue), WindowManager.shared.config.keyboardHelp,
                  !Hotkeys.shared.submap.isEmpty else { return }
            let helpKey = WindowManager.shared.config.keyboardHelpKey
            let held = keys.modeChord.first.map { " Or hold \($0) after you enter." } ?? ""
            present(Tip(id: known.rawValue, title: "See every key",
                        body: "In window mode, \(helpKey) shows what every key does.\(held)",
                        chords: [[helpKey]], place: .modeBar))
        }
    }

    func modeChanged(_ name: String) {
        pendingWork?.cancel()
        if name.isEmpty {
            if case .modeBar = global?.place { dismissGlobal() }
            return
        }
        modeEntries += 1
        guard modeEntries >= Self.modeEntriesNeeded, canShow(Known.keyHelp.rawValue) else { return }
        let work = DispatchWorkItem { [weak self] in self?.show(.keyHelp) }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func clicked(id: String, label: String, shortcut: [String]) {
        guard !shortcut.isEmpty, enabled, Onboarding.isDone else { return }
        var counts = defaults.dictionary(forKey: Self.clicksKey) as? [String: Int] ?? [:]
        counts[id, default: 0] += 1
        defaults.set(counts, forKey: Self.clicksKey)
        let tipID = "clicked.\(id)"
        guard counts[id, default: 0] >= Self.menuClicks, canShow(tipID) else { return }
        let keys = ShortcutIndex()
        let global = shortcut.contains { ["⌘", "⌥", "⌃"].contains($0) }
        let chords = global || keys.modeChord.isEmpty ? [shortcut] : [keys.modeChord, shortcut]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, canShow(tipID) else { return }
            present(Tip(id: tipID, title: "\(label) has a key", body: "Faster than the menu.",
                        chords: chords, place: .menuBar))
        }
    }

    func paneShown(_ pane: Pane) {
        let place = TipPlace.settings("pane.\(pane.rawValue)")
        if let current = settings, current.place != place { dismissSettings() }
        let keys = ShortcutIndex()
        let chord = keys.modeChord
        let tip: Tip?
        switch pane {
        case .shortcuts:
            tip = Tip(id: "settings.shortcuts", title: "Two sets of keys",
                      body: "Global keys work anywhere. The rest work in window mode, so they never clash with typing.",
                      chords: chord.isEmpty ? [] : [chord], place: place)
        case .layout:
            let next = keys.keys(WindowActions.cyclelayout.name, "next")
            tip = next.isEmpty ? nil : Tip(id: "settings.layout", title: "Step through these layouts",
                                           body: "In window mode, \(next.joined()) steps through this list.",
                                           chords: chord.isEmpty ? [next] : [chord, next], place: place)
        case .windows:
            let float = keys.keys(WindowActions.togglefloating.name)
            let body = "This list floats whole apps. \(float.joined()) in window mode floats one window."
            tip = float.isEmpty ? nil : Tip(id: "settings.windows", title: "Float a single window",
                                            body: body,
                                            chords: chord.isEmpty ? [float] : [chord, float], place: place)
        default:
            tip = nil
        }
        guard let tip, canShow(tip.id) else { return }
        var opens = defaults.dictionary(forKey: Self.panesKey) as? [String: Int] ?? [:]
        opens[tip.id, default: 0] += 1
        defaults.set(opens, forKey: Self.panesKey)
        guard opens[tip.id, default: 0] >= Self.paneOpens else { return }
        pendingWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, canShow(tip.id), SettingsWindow.shared.settingsUI.pane == pane else { return }
            present(tip)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.paneDelay, execute: work)
    }

    func settingsClosed() {
        pendingWork?.cancel()
        dismissSettings()
    }

    func present(_ tip: Tip) {
        switch tip.place {
        case .settings:
            withAnimation(Motion.easeOut) { settings = tip }
        case .menuBar, .modeBar:
            guard showPanel(tip) else { return }
        }
        markSeen(tip.id)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.lastKey)
    }

    func dismiss(_ tip: Tip) {
        if settings == tip { dismissSettings() } else if global == tip { dismissGlobal() }
    }

    func noMore() {
        enabled = false
    }

    func dismissAll() {
        pendingWork?.cancel()
        dismissSettings()
        dismissGlobal()
    }
}
