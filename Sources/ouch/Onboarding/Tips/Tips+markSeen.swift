import AppKit
import SwiftUI

extension Tips {
    func markSeen(_ id: String) {
        guard !seen.contains(id) else { return }
        defaults.set(Array(seen.union([id])), forKey: Self.seenKey)
    }

    func markSeen(_ k: Known) { markSeen(k.rawValue) }

    func launched() {
        _ = daysUsed
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            if !TutorialLesson.finishedOnce, TutorialLesson.paused == nil { self?.show(.tutorial) }
        }
    }

    func canShow(_ id: String) -> Bool {
        enabled && daysUsed >= Self.minDaysUsed && rested && Onboarding.isDone && !Onboarding.shared.isRunning && !seen.contains(id) && settings == nil && global == nil
            && !SortPanel.shared.isOpen
    }

    func show(_ k: Known) {
        switch k {
        case .tutorial:
            guard canShow(k.rawValue) else { return }
            present(Tip(id: k.rawValue, title: "Make the keys stick",
                        body: "Keyboard Tutorial, in this menu, drills them a chapter at a time.",
                        place: .menuBar, action: ("Start tutorial", { Onboarding.shared.startTutorial() })))
        case .keyHelp:
            let keys = ShortcutIndex()
            guard canShow(k.rawValue), WindowManager.shared.config.keyboardHelp, !Hotkeys.shared.submap.isEmpty else { return }
            let helpKey = WindowManager.shared.config.keyboardHelpKey
            let held = keys.modeChord.first.map { " Or hold \($0) after you enter." } ?? ""
            present(Tip(id: k.rawValue, title: "See every key", body: "In window mode, \(helpKey) shows what every key does.\(held)",
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
        if let s = settings, s.place != .settings("pane.\(pane.rawValue)") { dismissSettings() }
        let keys = ShortcutIndex()
        let chord = keys.modeChord
        let tip: Tip?
        switch pane {
        case .shortcuts:
            tip = Tip(id: "settings.shortcuts", title: "Two sets of keys",
                      body: "Global keys work anywhere. The rest work in window mode, so they never clash with typing.",
                      chords: chord.isEmpty ? [] : [chord], place: .settings("pane.\(pane.rawValue)"))
        case .layout:
            let next = keys.keys("cyclelayout", "next")
            tip = next.isEmpty ? nil : Tip(id: "settings.layout", title: "Step through these layouts",
                                           body: "In window mode, \(next.joined()) steps through this list.",
                                           chords: chord.isEmpty ? [next] : [chord, next], place: .settings("pane.\(pane.rawValue)"))
        case .windows:
            let float = keys.keys("togglefloating")
            tip = float.isEmpty ? nil : Tip(id: "settings.windows", title: "Float a single window",
                                            body: "This list floats whole apps. \(float.joined()) in window mode floats one window.",
                                            chords: chord.isEmpty ? [float] : [chord, float], place: .settings("pane.\(pane.rawValue)"))
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
            guard let self, canShow(tip.id), SettingsWindow.shared.ui.pane == pane else { return }
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
