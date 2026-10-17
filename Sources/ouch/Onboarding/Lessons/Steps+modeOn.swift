import AppKit

extension Steps {
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
                 text: recall ? "From memory." : (keys.isEmpty ? "Click anywhere. The edge glow fades."
                    : "Press \(KeyWords.list(keys, or: true)) or click anywhere. The edge glow fades."),
                 target: .mode, caps: keys, recall: recall, accept: { e in
                     if case .mode(let n) = e, n.isEmpty { return "" }
                     if case .tick = e, Hotkeys.shared.submap.isEmpty { return "" }
                     return nil
                 }, simulate: { Hotkeys.shared.setSubmap("") })
        }
    }

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
            var seen: Set<String> = []
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

}
