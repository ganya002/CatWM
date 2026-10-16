// Onboarding: lesson scripts (the tour and the tutorial) and their step builders.
import AppKit

// The coach's scripts: the short tour that ends onboarding, and the longer tutorial that drills the
// keys until they stick. Both are built from the same step builders, which read the user's own binds
// and leave a step out when nothing is bound for it.

// MARK: - The user's binds

struct BindBook {
    let binds: [KeyBinding]
    /// The global bind that enters window mode, and the mode's name ("" without one).
    let enter: KeyBinding?
    let mode: String

    init(binds: [KeyBinding]) {
        self.binds = binds
        enter = binds.first { $0.submap.isEmpty && $0.dispatcher == "submap" && !["", "reset"].contains($0.arg.lowercased()) }
        mode = enter?.arg ?? ""
    }

    /// A bind in window mode, or a global one with `global`.
    func find(_ dispatchers: [String], _ arg: String? = nil, global: Bool = false) -> KeyBinding? {
        let submap = global ? "" : mode
        return binds.first { b in
            b.submap == submap && dispatchers.contains(b.dispatcher) && (arg.map { KeyWords.same(b.arg, $0) } ?? true)
        }
    }

    var exits: [KeyBinding] {
        binds.filter { $0.submap == mode && $0.dispatcher == "submap" && ["", "reset"].contains($0.arg.lowercased()) && $0.mods.isEmpty }
    }

    func enterCaps(long: Bool) -> [String] { enter.map { KeyWords.caps($0, long: long) } ?? [] }

    /// W moves focus up: the WASD set.
    var wasd: Bool { find(["movefocus"], "u")?.keyCode == 13 }

    /// Directions in the order their keys sit: H J K L, or W A S D.
    var directions: [String] { wasd ? ["u", "l", "d", "r"] : ["l", "d", "u", "r"] }

    /// Grow and shrink binds for the main pane.
    var resize: (grow: KeyBinding, shrink: KeyBinding)? {
        let ratio = binds.filter { $0.submap == mode }.compactMap { b in KeyWords.ratioDirection(b.dispatcher, b.arg).map { (b, $0) } }
        guard let g = ratio.first(where: { $0.1 })?.0, let s = ratio.first(where: { !$0.1 })?.0 else { return nil }
        return (g, s)
    }
}

// MARK: - Shared steps

/// One planned step: how to build it when it starts.
struct PlannedStep {
    let build: (Coach) -> Coach.Step
}

/// Step builders shared by the tour and the tutorial. Each returns nil when the binds it needs are missing.
enum Steps {
    typealias Step = Coach.Step

    static func modeOn(_ c: Coach, title: String? = nil, text: String? = nil) -> PlannedStep? {
        let b = c.book
        guard b.enter != nil, !b.mode.isEmpty else { return nil }
        let name = b.mode.lowercased()
        return PlannedStep { c in
            Step(title: title ?? "\(name.capitalized) mode",
                 text: text ?? "Access all shortcuts within \(name) mode. Central concept of this tiling manager.",
                 caps: c.book.enterCaps(long: true), accept: { e in
                     if case .mode(let n) = e, !n.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap(c.book.mode) })
        }
    }

    static func modeOff(_ c: Coach, recall: Bool = false) -> PlannedStep? {
        let b = c.book
        guard !b.mode.isEmpty else { return nil }
        let keys = b.exits.map { KeyWords.keyLabel($0.keyCode, long: false) }
        let name = b.mode.lowercased()
        return PlannedStep { _ in
            Step(title: "Leave \(name) mode",
                 // The mode shows as a glow around the screen; there's no bar to point at.
                 text: recall ? "From memory." : (keys.isEmpty ? "Click anywhere. The edge glow fades."
                    : "Press \(KeyWords.list(keys, or: true)) or click anywhere. The edge glow fades."),
                 target: .mode, caps: keys, recall: recall, accept: { e in
                     // Also when it's already off: a click turns it off without a mode event reaching us.
                     if case .mode(let n) = e, n.isEmpty { return "" }
                     if case .tick = e, Hotkeys.shared.submap.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap("") })
        }
    }

    /// `?` opens the keyboard help in the mode, and again closes it.
    static func help(_ c: Coach) -> PlannedStep? {
        guard c.wm.config.keyboardHelp, !c.book.mode.isEmpty else { return nil }
        let key = c.wm.config.keyboardHelpKey
        return PlannedStep { _ in
            var opened = false
            return Step(title: "Key Map",
                        text: "If you ever forget a shortcut, you'll find an overview easily here.",
                        caps: [key, key], tokens: ["open", "close"], needsMode: true, accept: { e in
                            guard case .tick = e else { return nil }
                            if KeyHelp.shared.isVisible { opened = true; return "open" }
                            return opened ? "close" : nil
                        }, simulate: { KeyHelp.shared.toggle() })
        }
    }

    static func focus(_ c: Coach) -> PlannedStep? {
        let b = c.book
        let dirs = b.directions.compactMap { d in b.find(["movefocus"], d).map { (d, $0) } }
        guard dirs.count == 4 else { return nil }
        let keys = dirs.map { KeyWords.keyLabel($0.1.keyCode, long: false) }
        return PlannedStep { c in
            var left = c.book.directions
            return Step(title: "Move focus",
                        text: "",
                        target: .window, caps: keys, tokens: b.directions, needsMode: true, count: 4,
                        accept: { e in
                            guard case .command("movefocus", let a, _) = e else { return nil }
                            return KeyWords.dirToken(a)
                        }, simulate: {
                            let d = left.isEmpty ? "r" : left.removeFirst()
                            c.wm.dispatch("movefocus", d)
                        })
        }
    }

    static func cycle(_ c: Coach) -> PlannedStep? {
        guard let next = c.book.find(["cyclenext"], "") else { return nil }
        let key = KeyWords.keyLabel(next.keyCode, long: false)
        return PlannedStep { c in
            Step(title: "Next window",
                 text: "\(key) cycles focus through every window. Press it a few times.",
                 target: .window, caps: KeyWords.caps(next, long: false), needsMode: true, count: 3,
                 accept: { e in
                     if case .command("cyclenext", _, _) = e { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("cyclenext", "") })
        }
    }

    static func move(_ c: Coach) -> PlannedStep? {
        let b = c.book
        let dirs = b.directions.compactMap { d in b.find(["movewindow", "swapwindow"], d) }
        guard dirs.count == 4 else { return nil }
        let mods = KeyWords.modLabels(dirs[0].mods, long: true)
        let keys = dirs.map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { c in
            Step(title: "Move a window",
                 text: "",
                 target: .window, caps: mods + keys, needsMode: true, count: 2,
                 accept: { e in
                     guard case .command(let d, let a, _) = e else { return nil }
                     if d == "movewindow", !a.lowercased().hasPrefix("mon:") { return KeyWords.dirToken(a) ?? "" }
                     if ["swapwindow", "swapnext"].contains(d) || (d == "layoutmsg" && a.lowercased().hasPrefix("swap")) { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("swapnext", "") })
        }
    }

    static func main(_ c: Coach) -> PlannedStep? {
        guard let swap = c.book.find(["layoutmsg"], "swapwithmaster") else { return nil }
        return PlannedStep { c in
            Step(title: "Promote a window",
                 text: "",
                 target: .window, caps: KeyWords.caps(swap, long: false), needsMode: true,
                 accept: { e in
                     if case .command("layoutmsg", let a, _) = e, a.lowercased() == "swapwithmaster" { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("layoutmsg", "swapwithmaster") })
        }
    }

    static func masters(_ c: Coach) -> PlannedStep? {
        guard let add = c.book.find(["layoutmsg"], "addmaster"), let remove = c.book.find(["layoutmsg"], "removemaster") else { return nil }
        return PlannedStep { c in
            var adding = true
            var seen: Set<String> = [] // each action counts once, so the step needs both
            return Step(title: "More main windows",
                        text: "\(KeyWords.keyWord(add)) adds a window to the main pane, \(KeyWords.keyWord(remove)) takes one out. Try both.",
                        target: .window, caps: KeyWords.caps(add, long: false) + [KeyWords.keyLabel(remove.keyCode, long: false)],
                        tokens: [], needsMode: true, count: 2,
                        accept: { e in
                            guard case .command("layoutmsg", let a, _) = e else { return nil }
                            guard ["addmaster", "removemaster"].contains(a.lowercased()) else { return nil }
                            return seen.insert(a.lowercased()).inserted ? "" : nil
                        }, simulate: {
                            c.wm.dispatch("layoutmsg", adding ? "addmaster" : "removemaster")
                            adding.toggle()
                        })
        }
    }

    static func resize(_ c: Coach) -> PlannedStep? {
        guard let (grow, shrink) = c.book.resize else { return nil }
        return PlannedStep { c in
            var growing = true
            return Step(title: "Resize the main pane",
                 text: "",
                 target: .window, caps: KeyWords.caps(shrink, long: false) + KeyWords.caps(grow, long: false),
                 tokens: KeyWords.caps(shrink, long: false).count == 1 && KeyWords.caps(grow, long: false).count == 1 ? ["shrink", "grow"] : [],
                 needsMode: true, count: 2,
                 accept: { e in
                     guard case .command(let d, let a, _) = e, let g = KeyWords.ratioDirection(d, a) else { return nil }
                     return g ? "grow" : "shrink"
                 }, simulate: {
                     c.wm.dispatch("splitratio", growing ? "+0.1" : "-0.1")
                     growing.toggle()
                 })
        }
    }

    static func zoom(_ c: Coach) -> PlannedStep? {
        guard let zoom = c.book.find(["fullscreen"]) else { return nil }
        return PlannedStep { c in
            Step(title: "Fullscreen", text: "",
                 target: .window, caps: KeyWords.caps(zoom, long: false), needsMode: true, count: 2,
                 accept: { e in
                     if case .command("fullscreen", _, _) = e { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("fullscreen", "") })
        }
    }

    static func float(_ c: Coach) -> PlannedStep? {
        guard let float = c.book.find(["togglefloating"]) else { return nil }
        return PlannedStep { c in
            Step(title: "Float a window",
                 text: "PS: this window will not tile.",
                 target: .window, caps: KeyWords.caps(float, long: false), needsMode: true, count: 2,
                 accept: { e in
                     if case .command("togglefloating", _, _) = e { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("togglefloating", "") })
        }
    }

    static func retile(_ c: Coach) -> PlannedStep? {
        guard let retile = c.book.find(["retile", "reevaluate"]) else { return nil }
        let key = KeyWords.keyLabel(retile.keyCode, long: false)
        return PlannedStep { c in
            Step(title: "Snap back",
                 text: "\(key) puts every window back in the layout.",
                 target: .window, caps: KeyWords.caps(retile, long: false), needsMode: true,
                 accept: { e in
                     if case .command(let d, _, _) = e, ["retile", "reevaluate"].contains(d) { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("retile", "") })
        }
    }

    static func layouts(_ c: Coach) -> PlannedStep? {
        guard let next = c.book.find(["cyclelayout"], "next") else { return nil }
        let prev = c.book.find(["cyclelayout"], "prev")
        let keys = [next, prev].compactMap { $0 }.map { KeyWords.caps($0, long: false).joined() } // WASD: R and ⇧R
        return PlannedStep { c in
            Step(title: "Change layout",
                 text: "",
                 target: .window, caps: keys, tokens: keys.count > 1 ? ["next", "prev"] : [], needsMode: true, count: 2,
                 accept: { e in
                     guard case .command("cyclelayout", let a, _) = e else { return nil }
                     return a.lowercased().hasPrefix("prev") ? "prev" : "next"
                 }, simulate: { c.wm.dispatch("cyclelayout", "next") })
        }
    }

    static func visit(_ c: Coach) -> PlannedStep? {
        guard let other = c.other, let visit = c.book.find(["workspace"], other) else { return nil }
        return PlannedStep { c in
            Step(title: "Workspaces",
                 text: "",
                 target: .bar, caps: KeyWords.caps(visit, long: true), needsMode: true,
                 accept: { e in
                     if case .command("workspace", _, _) = e, c.wm.currentWorkspace == other { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("workspace", other) })
        }
    }

    static func back(_ c: Coach) -> PlannedStep? {
        guard let desk = c.desk, c.other != nil, let back = c.book.find(["workspace"], desk) else { return nil }
        return PlannedStep { c in
            Step(title: "Nothing closed",
                 text: "Hidden workspaces keep their windows. \(KeyWords.keyLabel(back.keyCode, long: false)) goes back to \(desk).",
                 target: .bar, caps: KeyWords.caps(back, long: true), needsMode: true,
                 accept: { e in
                     if case .command("workspace", _, _) = e, c.wm.currentWorkspace == desk { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("workspace", desk) })
        }
    }

    /// WASD's Q and E: the workspace before and after.
    static func neighbours(_ c: Coach) -> PlannedStep? {
        guard let next = c.book.find(["workspace"], "e+1"), let prev = c.book.find(["workspace"], "e-1"), c.desk != nil else { return nil }
        let keys = [prev, next].map { KeyWords.keyLabel($0.keyCode, long: false) }
        return PlannedStep { c in
            Step(title: "Next and previous",
                 text: "\(keys[1]) is the next workspace, \(keys[0]) the previous. Go and come back.",
                 target: .bar, caps: keys, tokens: ["prev", "next"], needsMode: true, count: 2,
                 accept: { e in
                     guard case .command("workspace", let a, _) = e else { return nil }
                     return a.hasPrefix("e-") ? "prev" : a.hasPrefix("e+") ? "next" : nil
                 }, simulate: {
                     c.wm.dispatch("workspace", c.wm.currentWorkspace == c.desk ? "e+1" : "e-1")
                 })
        }
    }

    static func send(_ c: Coach) -> PlannedStep? {
        guard let sendTo = c.sendTo, let send = c.book.find(["movetoworkspace", "movetoworkspacesilent"], sendTo) else { return nil }
        return PlannedStep { c in
            Step(title: "Move to a workspace", text: "",
                 target: .window, caps: KeyWords.caps(send, long: true), needsMode: true,
                 accept: { e in
                     if case .command(let d, _, _) = e, d.hasPrefix("movetoworkspace") { return "" }
                     return nil
                 }, simulate: { c.wm.dispatch("movetoworkspace", sendTo) })
        }
    }

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

    /// Points at the menu bar: Sort Windows, without opening it on the practice desk.
    static func sortIntro(_ c: Coach) -> PlannedStep? {
        guard c.wm.config.virtualWorkspaces, let sort = c.book.find(["sort"], global: true) ?? c.book.find(["sort"]) else { return nil }
        return PlannedStep { _ in
            Step(title: "Sort Windows", text: "", target: .bar, caps: KeyWords.caps(sort, long: true), button: "Next", count: 0)
        }
    }

    /// Opens Sort Windows for real, then closes it with esc, which changes nothing.
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

    // MARK: Recall drills

    /// "Focus Notes": pick a window that isn't focused, and wait until it is. Keys stay hidden at first.
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

    /// "Put Mail in the main pane".
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

    /// "Switch to Wide": cycle until the named layout is up.
    static func layoutDrill(_ c: Coach) -> PlannedStep? {
        guard let next = c.book.find(["cyclelayout"], "next") else { return nil }
        let options = c.wm.config.layouts.filter { ![.fullscreen, .floating].contains($0) }
        guard options.count > 1 else { return nil }
        let prev = c.book.find(["cyclelayout"], "prev")
        let keys = [next, prev].compactMap { $0 }.map { KeyWords.caps($0, long: false).joined() } // WASD: R and ⇧R
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

    /// "Go to workspace 7 and back" style: visit the other desk.
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

    // MARK: Bookends

    static func intro(_ c: Coach, title: String, button: String) -> PlannedStep {
        PlannedStep { c in
            let text: String
            if let desk = c.desk, let other = c.other {
                text = "\(KeyWords.count(PracticeDesk.deskCount)) practice windows on workspace \(desk), \(KeyWords.count(PracticeDesk.otherCount).lowercased()) on \(other)."
                    + (c.original.map { " Yours wait on \($0)." } ?? "")
            } else {
                text = "\(KeyWords.count(PracticeDesk.deskCount + PracticeDesk.otherCount)) practice windows. Your apps aren't touched."
            }
            return Step(title: title, text: text, button: button, count: 0)
        }
    }

    /// The last card: every key the lesson taught, in the user's own binds. Groups with no binds drop out.
    static func summary(_ c: Coach, title: String, tutorial: Bool = false) -> PlannedStep {
        let b = c.book
        func cap(_ k: KeyBinding?) -> [String] { k.map { KeyWords.caps($0, long: false) } ?? [] }
        var inMode: [(caps: [String], label: String)] = []
        let dirs = b.directions.compactMap { b.find(["movefocus"], $0) }
        if dirs.count == 4 { inMode.append((dirs.map { KeyWords.keyLabel($0.keyCode, long: false) }, "Move focus")) }
        let moves = b.directions.compactMap { b.find(["movewindow", "swapwindow"], $0) }
        if moves.count == 4 {
            inMode.append((KeyWords.modLabels(moves[0].mods, long: false) + moves.map { KeyWords.keyLabel($0.keyCode, long: false) },
                           "Move the window"))
        }
        if let s = b.find(["layoutmsg"], "swapwithmaster") { inMode.append((cap(s), "Swap with the main pane")) }
        if let (g, s) = b.resize { inMode.append((cap(s) + cap(g), "Shrink / grow")) }
        if let n = b.find(["cyclelayout"], "next") { inMode.append((cap(n), "Next layout")) }
        if let w = b.find(["workspace"], "1") { inMode.append((KeyWords.modLabels(w.mods, long: false) + ["1–0"], "Switch workspace")) }
        if b.enter != nil, c.wm.config.keyboardHelp { inMode.append(([c.wm.config.keyboardHelpKey], "Keyboard help")) }
        var more: [(caps: [String], label: String)] = []
        if let f = b.find(["fullscreen"]) { more.append((cap(f), "Zoom")) }
        if let f = b.find(["nativefullscreen"]) { more.append((cap(f), "macOS full screen")) }
        if let f = b.find(["togglefloating"]) { more.append((cap(f), "Float or tile")) }
        var anywhere: [(caps: [String], label: String)] = []
        if let s = b.find(["sort"], global: true) { anywhere.append((cap(s), "Sort windows")) }
        if let g = b.find(["workspace"], "1", global: true) { anywhere.append((KeyWords.modLabels(g.mods, long: false) + ["1–0"], "Switch workspace")) }

        var summary = Coach.Summary(tutorial: tutorial)
        if b.enter != nil {
            summary.modeCaps = b.enterCaps(long: false)
            summary.modeName = "\(b.mode.capitalized) mode"
            if c.wm.config.keyboardHelp { summary.helpKey = c.wm.config.keyboardHelpKey }
        }
        let modeTitle = b.mode.isEmpty ? "Keys" : "In \(b.mode) mode"
        summary.groups = [.init(title: modeTitle, column: 1, rows: inMode),
                          .init(title: "More", column: 2, rows: more),
                          .init(title: "From anywhere", column: 2, rows: anywhere)].filter { !$0.rows.isEmpty }
        return PlannedStep { _ in
            Step(title: title,
                 text: "Your own windows are back where you left them.",
                 button: "Finish", count: 0, summary: summary)
        }
    }
}

// MARK: - The onboarding tour

/// The tour at the end of onboarding: every main key once, on the practice desk, in about three minutes.
final class TourLesson: Lesson {
    private var plan: [PlannedStep] = []
    let pausable = false
    let startIndex = 0
    var count: Int { plan.count }

    func prepare(_ c: Coach) {
        plan = [Steps.modeOn(c), Steps.help(c), Steps.focus(c), Steps.move(c), Steps.main(c), Steps.resize(c),
                Steps.zoom(c), Steps.float(c), Steps.layouts(c), Steps.visit(c), Steps.send(c),
                Steps.modeOff(c), Steps.global(c), Steps.sortIntro(c)].compactMap { $0 }
        plan.append(Steps.summary(c, title: "You learned the *basics*", tutorial: true))
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].build(coach) }

    func ended(_ how: Coach.Ending, at index: Int) {}
}

// MARK: - The tutorial

/// The long tutorial: chapters that each teach a few keys and then drill them from memory. It can be
/// paused at any step; it comes back at the start of that chapter.
final class TutorialLesson: Lesson {
    struct Chapter {
        let id: String
        let name: String
        let steps: [PlannedStep]
    }

    static let savedKey = "tutorial.chapter"
    private static let doneKey = "tutorial.done"

    private var chapters: [Chapter] = []
    private var plan: [(chapter: Int, step: PlannedStep)] = []
    private(set) var startIndex = 0
    let pausable = true
    var count: Int { plan.count }

    /// Where a paused tutorial picks up, if it was paused.
    static var paused: (id: String, name: String)? {
        guard let s = UserDefaults.standard.string(forKey: savedKey) else { return nil }
        let parts = s.split(separator: "|", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }
    static var finishedOnce: Bool { UserDefaults.standard.bool(forKey: doneKey) }
    static func forget() { UserDefaults.standard.removeObject(forKey: savedKey) }

    func prepare(_ c: Coach) {
        func chapter(_ id: String, _ name: String, _ steps: [PlannedStep?]) {
            let list = steps.compactMap { $0 }
            if !list.isEmpty { chapters.append(Chapter(id: id, name: name, steps: list)) }
        }
        chapter("welcome", "Welcome", [Steps.intro(c, title: "Learn every key", button: "Start")])
        chapter("mode", "Window mode", [Steps.modeOn(c), Steps.modeOff(c), Steps.modeDrill(c), Steps.help(c)])
        chapter("focus", "Focus", [Steps.focus(c), Steps.cycle(c), Steps.focusDrill(c), Steps.focusDrill(c), Steps.focusDrill(c)])
        chapter("move", "Moving windows", [Steps.move(c), Steps.main(c), Steps.mainDrill(c), Steps.mainDrill(c)])
        chapter("main", "The main pane", [Steps.masters(c), Steps.resize(c)])
        chapter("layouts", "Layouts", [Steps.layouts(c), Steps.layoutDrill(c), Steps.layoutDrill(c)])
        chapter("zoom", "Zoom and float", [Steps.zoom(c), Steps.float(c), Steps.retile(c)])
        chapter("workspaces", "Workspaces", [Steps.visit(c), Steps.back(c), Steps.neighbours(c), Steps.workspaceDrill(c), Steps.send(c)])
        chapter("global", "Global keys", [Steps.modeOff(c), Steps.global(c)])
        chapter("displays", "Displays", [Steps.monitor(c)])
        chapter("sort", "Sorting", Steps.sortTry(c))
        chapter("done", "Done", [Steps.summary(c, title: "That's every key")])
        for (i, ch) in chapters.enumerated() { plan += ch.steps.map { (i, $0) } }
        if let saved = Self.paused, let i = chapters.firstIndex(where: { $0.id == saved.id }),
           let start = plan.firstIndex(where: { $0.chapter == i }) {
            startIndex = start
        }
    }

    func step(_ i: Int, in coach: Coach) -> Coach.Step { plan[i].step.build(coach) }

    func ended(_ how: Coach.Ending, at index: Int) {
        let d = UserDefaults.standard
        switch how {
        case .finished, .tutorial:
            Self.forget()
            d.set(true, forKey: Self.doneKey)
        case .paused, .skipped:
            let ch = chapters[plan[min(index, plan.count - 1)].chapter]
            if ch.id == "welcome" || ch.id == "done" { Self.forget() } else { d.set("\(ch.id)|\(ch.name)", forKey: Self.savedKey) }
        }
    }
}

// MARK: - Keycap labels and words

enum KeyWords {
    static func same(_ a: String, _ b: String) -> Bool {
        if let x = Direction(a), let y = Direction(b) { return x == y }
        let la = a.lowercased(), lb = b.lowercased()
        return la == lb || (lb == "prev" && la.hasPrefix("prev"))
    }

    /// l, d, u or r for any spelling of a direction.
    static func dirToken(_ a: String) -> String? {
        switch Direction(a) {
        case .left: "l"
        case .right: "r"
        case .up: "u"
        case .down: "d"
        case nil: nil
        }
    }

    static func dirWord(_ t: String) -> String {
        ["l": "left", "r": "right", "u": "up", "d": "down"][t] ?? t
    }

    /// For resize binds (`splitratio +0.05`, `layoutmsg mfact -0.05`): true if it grows the main pane.
    static func ratioDirection(_ dispatcher: String, _ arg: String) -> Bool? {
        var a = arg.lowercased().trimmingCharacters(in: .whitespaces)
        if dispatcher == "layoutmsg" {
            guard a.hasPrefix("mfact") else { return nil }
            a = String(a.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        } else if dispatcher != "splitratio" {
            return nil
        }
        guard !a.hasPrefix("exact") else { return nil }
        return !a.hasPrefix("-")
    }

    /// A shortcut as words for a sentence: "Shift-Period" rather than "⇧ .".
    static func keyWord(_ b: KeyBinding) -> String {
        let key: String
        switch b.keyCode {
        case 43: key = "Comma"
        case 47: key = "Period"
        case 27: key = "Minus"
        case 24: key = "Equals"
        default: key = keyLabel(b.keyCode, long: false)
        }
        return b.mods.isEmpty ? key : "\(modWords(b.mods))-\(key)"
    }

    static func caps(_ b: KeyBinding, long: Bool) -> [String] {
        modLabels(b.mods, long: long) + [keyLabel(b.keyCode, long: long)]
    }

    static func modLabels(_ f: CGEventFlags, long: Bool) -> [String] {
        var out: [String] = []
        if f.contains(.maskControl) { out.append(long ? "⌃ control" : "⌃") }
        if f.contains(.maskAlternate) { out.append(long ? "⌥ option" : "⌥") }
        if f.contains(.maskShift) { out.append(long ? "⇧ shift" : "⇧") }
        if f.contains(.maskCommand) { out.append("⌘") }
        return out
    }

    static func modWords(_ f: CGEventFlags) -> String {
        var out: [String] = []
        if f.contains(.maskControl) { out.append("Control") }
        if f.contains(.maskAlternate) { out.append("Option") }
        if f.contains(.maskShift) { out.append("Shift") }
        if f.contains(.maskCommand) { out.append("Command") }
        return out.isEmpty ? "A key" : out.joined(separator: "-")
    }

    static func keyLabel(_ code: UInt16, long: Bool) -> String {
        switch code {
        case 57: return long ? "⇪ caps lock" : "⇪"
        case 53: return "esc"
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "space"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 43: return ","
        case 47: return "."
        case 27: return "−"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 41: return ";"
        case 44: return "/"
        default: return ConfigDocument.keyName(for: code)?.uppercased() ?? "?"
        }
    }

    /// "Five" rather than "5", for the start of a sentence.
    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US") // the lessons are in English
        return (f.string(from: n as NSNumber) ?? String(n)).capitalized
    }

    /// "H, J, K and L"
    static func list(_ items: [String], or: Bool = false) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + (or ? " or " : " and ") + items.last!
    }
}
