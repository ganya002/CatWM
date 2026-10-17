import AppKit

extension Steps {
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
        let keys = [next, prev].compactMap { $0 }.map { KeyWords.caps($0, long: false).joined() }
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

}
