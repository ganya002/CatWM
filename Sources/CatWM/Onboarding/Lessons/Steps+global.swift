import AppKit
import CatWMKit

extension Steps {
    static func global(_ coach: Coach) -> PlannedStep? {
        guard let desk = coach.desk,
              let global = coach.book.find([WindowActions.workspace], desk, global: true) else { return nil }
        return PlannedStep { coach in
            Step(title: "Switch workspaces", text: "",
                 target: .bar, caps: KeyWords.caps(global, long: true),
                 accept: { event in
                     if case .command(WindowActions.workspace.name, _, let inMode) = event, !inMode,
                        coach.windowManager.currentWorkspace == desk {
                         return ""
                     }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     DispatchQueue.main.async { coach.windowManager.dispatch(WindowActions.workspace.name, desk) }
                 })
        }
    }

    static func monitor(_ coach: Coach) -> PlannedStep? {
        guard NSScreen.screens.count > 1, let mon = coach.book.find([WindowActions.focusmonitor]) else { return nil }
        let key = KeyWords.keyLabel(mon.keyCode, long: false)
        return PlannedStep { coach in
            Step(title: "Other display",
                 text: "\(key) moves focus to the next display. Press it again to come back.",
                 target: .window, caps: KeyWords.caps(mon, long: false), needsMode: true, count: 2,
                 accept: { event in
                     if case .command(WindowActions.focusmonitor.name, _, _) = event { return "" }
                     return nil
                 }, simulate: { coach.windowManager.dispatch(WindowActions.focusmonitor.name, "+1") })
        }
    }

    static func sortIntro(_ coach: Coach) -> PlannedStep? {
        guard coach.windowManager.config.virtualWorkspaces,
              let sort = coach.book.find([WindowActions.sort], global: true) ?? coach.book.find([WindowActions.sort])
        else { return nil }
        return PlannedStep { _ in
            Step(title: "Overview", text: "", target: .bar, caps: KeyWords.caps(sort, long: true),
                 button: "Next", count: 0)
        }
    }

    static func sortTry(_ coach: Coach) -> [PlannedStep] {
        guard coach.windowManager.config.virtualWorkspaces,
              let sort = coach.book.find([WindowActions.sort], global: true) else { return [] }
        let shortcut = "\(KeyWords.modWords(sort.mods))-\(KeyWords.keyLabel(sort.keyCode, long: false))"
        let open = PlannedStep { _ in
            Step(title: "Overview",
                 text: "\(shortcut) splits a crowded workspace into several, by task. Open it.",
                 target: .bar, caps: KeyWords.caps(sort, long: true),
                 accept: { event in
                     if case .tick = event, SortPanel.shared.isOpen { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(""); SortPanel.shared.open() })
        }
        let close = PlannedStep { _ in
            Step(title: "Lanes are workspaces",
                 text: "Drag windows between them, or pick a grouping. Esc closes it without changes.",
                 target: .bar, caps: ["esc"],
                 accept: { event in
                     if case .tick = event, !SortPanel.shared.isOpen { return "" }
                     return nil
                 }, simulate: { SortPanel.shared.revert() })
        }
        return [open, close]
    }

    static func focusDrill(_ coach: Coach) -> PlannedStep? {
        guard focus(coach) != nil else { return nil }
        let book = coach.book
        let keys = book.directions
            .compactMap { book.find([WindowActions.movefocus], $0) }
            .map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { coach in
            let target = coach.visibleTitles.filter { $0 != coach.focusedTitle }.randomElement()
            return Step(title: "Focus \(target ?? "another window")", text: "From memory.",
                        target: .window, caps: keys, needsMode: true, recall: true,
                        accept: { event in
                            guard case .command(let dispatcher, _, _) = event,
                                  [WindowActions.movefocus.name, WindowActions.cyclenext.name].contains(dispatcher)
                            else { return nil }
                            return target == nil || coach.focusedTitle == target ? "" : nil
                        }, simulate: { coach.windowManager.dispatch(WindowActions.cyclenext.name, "") })
        }
    }

    static func mainDrill(_ coach: Coach) -> PlannedStep? {
        guard let swap = coach.book.find([WindowActions.layoutmsg], "swapwithmaster"), focus(coach) != nil else {
            return nil
        }
        return PlannedStep { coach in
            let target = coach.visibleTitles.filter { $0 != coach.mainTitle }.randomElement()
            return Step(title: "Put \(target ?? "another window") in the main pane",
                        text: "Focus it, then promote it.",
                        target: .window, caps: KeyWords.caps(swap, long: false), needsMode: true, recall: true,
                        accept: { event in
                            guard case .command(let dispatcher, let argument, _) = event else { return nil }
                            if let target { return coach.mainTitle == target ? "" : nil }
                            let swapped = dispatcher == WindowActions.layoutmsg.name
                                && argument.lowercased() == "swapwithmaster"
                            return swapped ? "" : nil
                        }, simulate: { coach.windowManager.dispatch(WindowActions.layoutmsg.name, "swapwithmaster") })
        }
    }

    static func layoutDrill(_ coach: Coach) -> PlannedStep? {
        guard let next = coach.book.find([WindowActions.cyclelayout], "next") else { return nil }
        let options = coach.windowManager.config.layouts.filter { ![.fullscreen, .floating].contains($0) }
        guard options.count > 1 else { return nil }
        let prev = coach.book.find([WindowActions.cyclelayout], "prev")
        let keys = [next, prev].compactMap(\.self).map { KeyWords.caps($0, long: false).joined() }
        return PlannedStep { coach in
            let now = coach.windowManager.menuBarState()?.layout
            let target = options.filter { $0 != now }.randomElement() ?? options[0]
            return Step(title: "Switch to \(target.title)", text: "From memory.",
                        target: .window, caps: keys, needsMode: true, recall: true,
                        accept: { event in
                            guard case .command = event else { return nil }
                            return coach.windowManager.menuBarState()?.layout == target ? "" : nil
                        }, simulate: { coach.windowManager.dispatch(WindowActions.cyclelayout.name, "next") })
        }
    }

    static func workspaceDrill(_ coach: Coach) -> PlannedStep? {
        guard let desk = coach.desk, let other = coach.other, coach.book.find([WindowActions.workspace], other) != nil,
              let back = coach.book.find([WindowActions.workspace], desk) else { return nil }
        let digits = [other, desk].map { $0 == "10" ? "0" : $0 }
        let caps: [String] = KeyWords.caps(back, long: false).dropLast() + digits
        return PlannedStep { coach in
            var went = false
            return Step(title: "Visit \(other), then come back to \(desk)", text: "From memory.",
                        target: .bar, caps: caps,
                        tokens: [], needsMode: false, recall: true, count: 1,
                        accept: { event in
                            guard case .command(WindowActions.workspace.name, _, _) = event else { return nil }
                            if coach.windowManager.currentWorkspace == other { went = true }
                            return went && coach.windowManager.currentWorkspace == desk ? "" : nil
                        }, simulate: {
                            let manager = coach.windowManager
                            let destination = manager.currentWorkspace == other ? desk : other
                            manager.dispatch(WindowActions.workspace.name, destination)
                        })
        }
    }

    static func modeDrill(_ coach: Coach) -> PlannedStep? {
        guard coach.book.enter != nil else { return nil }
        return PlannedStep { coach in
            Step(title: "Turn \(coach.book.mode.lowercased()) mode on", text: "From memory.",
                 target: .mode, caps: coach.book.enterCaps(long: true), recall: true,
                 accept: { event in
                     if case .mode(let submap) = event, !submap.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(coach.book.mode) })
        }
    }
}

extension Steps {
    static func switcher(_ coach: Coach) -> PlannedStep? {
        guard let bind = coach.book.find([WindowActions.switcher], "", global: true) else { return nil }
        return PlannedStep { coach in
            Step(title: "Switch to any window",
                 text: "Tap it for your last window. Hold it to see every window, type to search, then release.",
                 caps: KeyWords.caps(bind, long: true),
                 accept: { event in
                     if case .command(WindowActions.switcher.name, _, _) = event { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     DispatchQueue.main.async { coach.windowManager.dispatch(WindowActions.switcher.name, "") }
                 })
        }
    }
}

extension Steps {
    static func sendGlobal(_ coach: Coach) -> PlannedStep? {
        guard let sendTo = coach.sendTo,
              let send = coach.book.find([WindowActions.movetoworkspace], sendTo, global: true) else { return nil }
        return PlannedStep { coach in
            Step(title: "Move a window to a workspace",
                 text: "Hold the keys from anywhere. The window goes with you.",
                 target: .window, caps: KeyWords.caps(send, long: true),
                 accept: { event in
                     if case .command(WindowActions.movetoworkspace.name, _, _) = event { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     coach.windowManager.dispatch(WindowActions.movetoworkspace.name, sendTo)
                 })
        }
    }

    static func focusGlobal(_ coach: Coach) -> PlannedStep? {
        guard let focus = coach.book.find([WindowActions.movefocus], coach.book.directions[3], global: true) else {
            return nil
        }
        return PlannedStep { coach in
            Step(title: "Focus a window from any app",
                 text: "Hold the keys and use a direction. Window mode is not necessary.",
                 target: .window, caps: KeyWords.caps(focus, long: true),
                 accept: { event in
                     if case .command(WindowActions.movefocus.name, _, false) = event { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     coach.windowManager.dispatch(WindowActions.movefocus.name, focus.arg)
                 })
        }
    }
}

extension Steps {
    static func quickActions(_ coach: Coach) -> [PlannedStep] {
        let mods = coach.windowManager.config.mainMod.union(coach.book.enter?.mods ?? [])
        guard coach.windowManager.config.cursorActions, !coach.book.mode.isEmpty,
              let tap = KeyWords.modLabels(mods, long: true).first else { return [] }
        let open = PlannedStep { _ in
            Step(title: "Quick actions at the pointer",
                 text: "In window mode, tap \(tap) by itself. A menu opens at the pointer.",
                 target: .mode, caps: [tap], needsMode: true,
                 accept: { event in
                     if case .tick = event, CursorActions.shared.isMenuOpen { return "" }
                     return nil
                 }, simulate: { CursorActions.shared.tapped() })
        }
        let close = PlannedStep { _ in
            Step(title: "Templates and dim live here",
                 text: "Save this workspace, open a saved one, or dim the other windows. Esc closes it.",
                 target: .mode, caps: ["esc"],
                 accept: { event in
                     if case .tick = event, !CursorActions.shared.isMenuOpen { return "" }
                     return nil
                 }, simulate: { CursorActions.shared.dismissMenu() })
        }
        return [open, close]
    }
}
