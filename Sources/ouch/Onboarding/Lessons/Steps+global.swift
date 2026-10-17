import AppKit

extension Steps {
    static func global(_ c: Coach) -> PlannedStep? {
        guard let desk = c.desk, let global = c.book.find(["workspace"], desk, global: true) else { return nil }
        return PlannedStep { c in
            Step(title: "Switch workspaces", text: "",
                 target: .bar, caps: KeyWords.caps(global, long: true),
                 accept: { e in
                     if case .command("workspace", _, let inMode) = e, !inMode, c.wm.currentWorkspace == desk { return "" }
                     return nil
                 }, simulate: {
                     Hotkeys.shared.setSubmap("")
                     DispatchQueue.main.async { c.wm.dispatch("workspace", desk) }
                 })
        }
    }

    static func monitor(_ c: Coach) -> PlannedStep? {
        guard NSScreen.screens.count > 1, let mon = c.book.find(["focusmonitor"]) else { return nil }
        let key = KeyWords.keyLabel(mon.keyCode, long: false)
        return PlannedStep { c in
            Step(title: "Other display",
                 text: "\(key) moves focus to the next display. Press it again to come back.",
                 target: .window, caps: KeyWords.caps(mon, long: false), needsMode: true, count: 2,
                 accept: { e in
                     if case .command("focusmonitor", _, _) = e { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("focusmonitor", "+1") })
        }
    }

    static func sortIntro(_ c: Coach) -> PlannedStep? {
        guard c.wm.config.virtualWorkspaces, let sort = c.book.find(["sort"], global: true) ?? c.book.find(["sort"]) else { return nil }
        return PlannedStep { _ in
            Step(title: "Sort Windows", text: "", target: .bar, caps: KeyWords.caps(sort, long: true), button: "Next", count: 0)
        }
    }

    static func sortTry(_ c: Coach) -> [PlannedStep] {
        guard c.wm.config.virtualWorkspaces, let sort = c.book.find(["sort"], global: true) else { return [] }
        let open = PlannedStep { c in
            Step(title: "Sort Windows",
                 text: "\(KeyWords.modWords(sort.mods))-\(KeyWords.keyLabel(sort.keyCode, long: false)) splits a crowded workspace into several, by task. Open it.",
                 target: .bar, caps: KeyWords.caps(sort, long: true),
                 accept: { e in
                     if case .tick = e, SortPanel.shared.isOpen { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(""); SortPanel.shared.open() })
        }
        let close = PlannedStep { _ in
            Step(title: "Lanes are workspaces",
                 text: "Drag windows between them, or pick a grouping. Esc closes it without changes.",
                 target: .bar, caps: ["esc"],
                 accept: { e in
                     if case .tick = e, !SortPanel.shared.isOpen { return "" }
                     return nil
                 }, simulate: { SortPanel.shared.revert() })
        }
        return [open, close]
    }

    static func focusDrill(_ c: Coach) -> PlannedStep? {
        guard focus(c) != nil else { return nil }
        let b = c.book
        let keys = b.directions.compactMap { b.find(["movefocus"], $0) }.map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { c in
            let target = c.visibleTitles.filter { $0 != c.focusedTitle }.randomElement()
            return Step(title: "Focus \(target ?? "another window")", text: "From memory.",
                        target: .window, caps: keys, needsMode: true, recall: true,
                        accept: { e in
                            guard case .command(let d, _, _) = e, ["movefocus", "cyclenext"].contains(d) else { return nil }
                            return target == nil || c.focusedTitle == target ? "" : nil
                        }, simulate: { c.wm.dispatch("cyclenext", "") })
        }
    }

    static func mainDrill(_ c: Coach) -> PlannedStep? {
        guard let swap = c.book.find(["layoutmsg"], "swapwithmaster"), focus(c) != nil else { return nil }
        return PlannedStep { c in
            let target = c.visibleTitles.filter { $0 != c.mainTitle }.randomElement()
            return Step(title: "Put \(target ?? "another window") in the main pane", text: "Focus it, then promote it.",
                        target: .window, caps: KeyWords.caps(swap, long: false), needsMode: true, recall: true,
                        accept: { e in
                            guard case .command(let d, let a, _) = e else { return nil }
                            if let target { return c.mainTitle == target ? "" : nil }
                            return d == "layoutmsg" && a.lowercased() == "swapwithmaster" ? "" : nil
                        }, simulate: { c.wm.dispatch("layoutmsg", "swapwithmaster") })
        }
    }

    static func layoutDrill(_ c: Coach) -> PlannedStep? {
        guard let next = c.book.find(["cyclelayout"], "next") else { return nil }
        let options = c.wm.config.layouts.filter { ![.fullscreen, .floating].contains($0) }
        guard options.count > 1 else { return nil }
        let prev = c.book.find(["cyclelayout"], "prev")
        let keys = [next, prev].compactMap { $0 }.map { KeyWords.caps($0, long: false).joined() }
        return PlannedStep { c in
            let now = c.wm.menuBarState()?.layout
            let target = options.filter { $0 != now }.randomElement() ?? options[0]
            return Step(title: "Switch to \(target.title)", text: "From memory.",
                        target: .window, caps: keys, needsMode: true, recall: true,
                        accept: { e in
                            guard case .command = e else { return nil }
                            return c.wm.menuBarState()?.layout == target ? "" : nil
                        }, simulate: { c.wm.dispatch("cyclelayout", "next") })
        }
    }

    static func workspaceDrill(_ c: Coach) -> PlannedStep? {
        guard let desk = c.desk, let other = c.other, c.book.find(["workspace"], other) != nil,
              let back = c.book.find(["workspace"], desk) else { return nil }
        return PlannedStep { c in
            var went = false
            return Step(title: "Visit \(other), then come back to \(desk)", text: "From memory.",
                        target: .bar, caps: KeyWords.caps(back, long: false).dropLast() + [other, desk].map { $0 == "10" ? "0" : $0 },
                        tokens: [], needsMode: false, recall: true, count: 1,
                        accept: { e in
                            guard case .command("workspace", _, _) = e else { return nil }
                            if c.wm.currentWorkspace == other { went = true }
                            return went && c.wm.currentWorkspace == desk ? "" : nil
                        }, simulate: {
                            c.wm.dispatch("workspace", c.wm.currentWorkspace == other ? desk : other)
                        })
        }
    }

    static func modeDrill(_ c: Coach) -> PlannedStep? {
        guard c.book.enter != nil else { return nil }
        return PlannedStep { c in
            Step(title: "Turn \(c.book.mode.lowercased()) mode on", text: "From memory.",
                 target: .mode, caps: c.book.enterCaps(long: true), recall: true,
                 accept: { e in
                     if case .mode(let n) = e, !n.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(c.book.mode) })
        }
    }

}
